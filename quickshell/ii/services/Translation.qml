pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

Singleton {
    id: root

    property var translations: ({})
    property var generatedTranslations: ({})
    property var availableLanguages: []
    property var availableGeneratedLanguages: []
    property bool isScanning:
        scanLanguagesProcess.running
        || scanGeneratedLanguagesProcess.running
    property bool isLoading: false
    property string translationKeepSuffix: "/*keep*/"
    property string translationsDir:
        Quickshell.shellPath("translations")
    property string generatedTranslationsDir:
        Directories.shellConfig + "/translations"

    readonly property string requestedLanguage: {
        const configured =
            Config?.options.language.ui ?? "auto";
        return configured !== "auto"
            ? configured
            : Qt.locale().name;
    }

    readonly property string builtInLanguageCode:
        compatibleLanguage(
            requestedLanguage,
            availableLanguages,
            "en_US"
        )

    readonly property string generatedLanguageCode:
        compatibleLanguage(
            requestedLanguage,
            availableGeneratedLanguages,
            ""
        )

    readonly property string languageCode:
        generatedLanguageCode.length > 0
            ? generatedLanguageCode
            : builtInLanguageCode

    function compatibleLanguage(
        requested,
        available,
        fallback
    ) {
        if (available.includes(requested))
            return requested;

        const prefix = String(requested).split("_")[0];
        const compatible = available.find(
            language =>
                String(language).split("_")[0]
                === prefix
        );

        if (compatible)
            return compatible;

        return available.includes(fallback)
            ? fallback
            : "";
    }

    onLanguageCodeChanged: {
        print(
            "[Translation] Language changed to",
            root.languageCode.length > 0
                ? root.languageCode
                : "source strings"
        );
    }

    TranslationScanner {
        id: scanLanguagesProcess
        translationsDir: root.translationsDir
        fallbackLanguages: ["en_US"]

        onLanguagesScanned: languages => {
            root.availableLanguages = languages;
        }
    }

    TranslationScanner {
        id: scanGeneratedLanguagesProcess
        translationsDir:
            root.generatedTranslationsDir
        fallbackLanguages: []

        onLanguagesScanned: languages => {
            root.availableGeneratedLanguages =
                languages;
        }
    }

    TranslationReader {
        id: translationFileView
        translationsDir: root.translationsDir
        languageCode: root.builtInLanguageCode

        onContentLoaded: data => {
            root.translations = data;
            root.isLoading = false;
        }
    }

    TranslationReader {
        id: generatedTranslationFileView
        translationsDir:
            root.generatedTranslationsDir
        languageCode:
            root.generatedLanguageCode

        onContentLoaded: data => {
            root.generatedTranslations = data;
            root.isLoading = false;
        }
    }

    function hasTranslation(source, key) {
        return (
            source
            && Object.prototype.hasOwnProperty.call(
                source,
                key
            )
        );
    }

    function tr(text) {
        if (!text)
            return "";

        const key = text.toString();

        if (
            root.isLoading
            || (
                !root.hasTranslation(
                    root.translations,
                    key
                )
                && !root.hasTranslation(
                    root.generatedTranslations,
                    key
                )
            )
        ) {
            return key;
        }

        let translation =
            root.translations[key]
            || root.generatedTranslations[key]
            || key;

        if (
            translation.endsWith(
                root.translationKeepSuffix
            )
        ) {
            translation = translation
                .substring(
                    0,
                    translation.length
                    - root.translationKeepSuffix.length
                )
                .trim();
        }

        return translation;
    }

    component TranslationScanner: Process {
        id: translationScanner

        required property string translationsDir
        required property var fallbackLanguages
        signal languagesScanned(var languages)

        command: [
            "find",
            translationScanner.translationsDir,
            "-maxdepth", "1",
            "-name", "*.json",
            "-exec", "basename", "{}",
            ".json", ";"
        ]
        running: true

        stdout: StdioCollector {
            id: languagesCollector

            onStreamFinished: {
                const files =
                    languagesCollector.text
                        .trim()
                        .split("\n")
                        .map(file => file.trim())
                        .filter(file => file.length > 0)
                        .sort();

                translationScanner.languagesScanned(
                    files
                );
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                translationScanner.languagesScanned(
                    translationScanner
                        .fallbackLanguages
                );
            }
        }
    }

    component TranslationReader: FileView {
        id: translationReader

        required property string translationsDir
        required property string languageCode
        signal contentLoaded(var data)

        path:
            languageCode.length > 0
                ? (
                    `${translationsDir}/`
                    + `${languageCode}.json`
                )
                : ""

        onPathChanged: {
            if (path.length === 0) {
                translationReader.contentLoaded({});
                return;
            }

            translationReader.reload();
        }

        onLoaded: {
            try {
                const jsonData =
                    JSON.parse(text());
                translationReader.contentLoaded(
                    jsonData
                );
            } catch (error) {
                console.log(
                    "[Translation] Failed to parse",
                    path,
                    error
                );
                translationReader.contentLoaded({});
            }
        }

        onLoadFailed: error => {
            // A path is only assigned after the scanner found the
            // language file, so this is a genuine read error rather
            // than expected locale fallback.
            console.warn(
                "[Translation] Failed to read",
                path,
                error
            );
            translationReader.contentLoaded({});
        }
    }
}
