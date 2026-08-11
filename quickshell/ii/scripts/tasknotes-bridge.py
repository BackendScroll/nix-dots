#!/usr/bin/env python3
"""QuickShell bridge for Obsidian TaskNotes through the official Obsidian CLI.

TaskNotes and Obsidian own all live task and Pomodoro mutations. The bridge
uses `obsidian eval` for parameterized TaskNotes operations and
`obsidian command` for the plugin's registered Pomodoro commands.

The Markdown task files and daily notes remain durable data. Read-only
filesystem fallback is available when the CLI is unavailable; task creation
and ordinary task mutations retain the earlier safe filesystem fallback.

QuickShell never starts Obsidian implicitly. Background refreshes only use the
official CLI when an Obsidian desktop process is already running. Otherwise,
task operations use their filesystem fallback and Pomodoro reports unavailable.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any
from urllib.parse import quote

import yaml


WINDOWS_INVALID_FILENAME = re.compile(r'[<>:"/\\|?*\x00-\x1f]')
FRONTMATTER_DELIMITER = "---"
CLI_MARKER = "__QS_TASKNOTES_JSON__"
CLI_END_MARKER = "__QS_TASKNOTES_END__"


class BridgeError(RuntimeError):
    """User-facing bridge error."""


class CliUnavailable(BridgeError):
    """Obsidian CLI or the TaskNotes plugin is unavailable."""


class CliError(BridgeError):
    """Obsidian CLI completed but the requested operation failed."""


def emit(payload: dict[str, Any], exit_code: int = 0) -> None:
    print(json.dumps(payload, ensure_ascii=False))
    raise SystemExit(exit_code)


def now_iso() -> str:
    return dt.datetime.now().astimezone().isoformat(timespec="milliseconds")


def today_iso() -> str:
    return dt.date.today().isoformat()


def json_value(value: Any) -> Any:
    if isinstance(value, (dt.datetime, dt.date)):
        return value.isoformat()
    if isinstance(value, Path):
        return value.as_posix()
    if isinstance(value, dict):
        return {str(key): json_value(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return [json_value(item) for item in value]
    return value


def text_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, (dt.datetime, dt.date)):
        return value.isoformat()
    return str(value)


def list_value(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    if isinstance(value, tuple):
        return list(value)
    return [value]


def split_frontmatter(text: str) -> tuple[dict[str, Any], str]:
    normalized = text.replace("\r\n", "\n")

    if not normalized.startswith(f"{FRONTMATTER_DELIMITER}\n"):
        return {}, normalized

    lines = normalized.splitlines(keepends=True)
    closing_index: int | None = None

    for index in range(1, len(lines)):
        if lines[index].strip() == FRONTMATTER_DELIMITER:
            closing_index = index
            break

    if closing_index is None:
        raise BridgeError("Note has an unterminated YAML frontmatter block.")

    raw_yaml = "".join(lines[1:closing_index])
    body = "".join(lines[closing_index + 1 :])

    try:
        metadata = yaml.safe_load(raw_yaml) or {}
    except yaml.YAMLError as error:
        raise BridgeError(f"Invalid YAML frontmatter: {error}") from error

    if not isinstance(metadata, dict):
        raise BridgeError("Frontmatter must be a YAML mapping.")

    return metadata, body


def render_note(metadata: dict[str, Any], body: str) -> str:
    yaml_text = yaml.safe_dump(
        metadata,
        allow_unicode=True,
        default_flow_style=False,
        sort_keys=False,
        width=1000,
    ).rstrip()

    normalized_body = body.replace("\r\n", "\n").lstrip("\n")
    if normalized_body and not normalized_body.endswith("\n"):
        normalized_body += "\n"

    return (
        f"{FRONTMATTER_DELIMITER}\n"
        f"{yaml_text}\n"
        f"{FRONTMATTER_DELIMITER}\n"
        f"{normalized_body}"
    )


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=path.parent,
        text=True,
    )
    temporary_path = Path(temporary_name)

    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())

        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except json.JSONDecodeError as error:
        raise BridgeError(f"Invalid JSON in {path}: {error}") from error

    if not isinstance(value, dict):
        raise BridgeError(f"{path} must contain a JSON object.")

    return value


def parse_timestamp(value: Any) -> dt.datetime | None:
    text = text_value(value).strip()
    if not text:
        return None

    try:
        return dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None


def session_minutes(session: dict[str, Any]) -> float:
    periods = list_value(session.get("activePeriods"))
    total_seconds = 0.0

    for period in periods:
        if not isinstance(period, dict):
            continue
        start = parse_timestamp(period.get("startTime"))
        end = parse_timestamp(period.get("endTime"))
        if start and end and end >= start:
            total_seconds += (end - start).total_seconds()

    if total_seconds <= 0:
        start = parse_timestamp(session.get("startTime"))
        end = parse_timestamp(session.get("endTime"))
        if start and end and end >= start:
            total_seconds = (end - start).total_seconds()

    return total_seconds / 60.0


def javascript_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


CLI_ACTIONS = {
    "command",
    "commands",
    "eval",
    "help",
    "version",
}


def process_belongs_to_current_user(process_path: Path) -> bool:
    try:
        status = (process_path / "status").read_text(
            encoding="utf-8",
            errors="replace",
        )
    except OSError:
        return False

    match = re.search(r"^Uid:\s+(\d+)", status, re.MULTILINE)
    return bool(match and int(match.group(1)) == os.getuid())


def process_identity(process_path: Path) -> tuple[str, str, list[str]]:
    try:
        comm = (process_path / "comm").read_text(
            encoding="utf-8",
            errors="replace",
        ).strip()
    except OSError:
        comm = ""

    try:
        executable = os.readlink(process_path / "exe")
    except OSError:
        executable = ""

    try:
        raw_arguments = (process_path / "cmdline").read_bytes()
        arguments = [
            argument.decode("utf-8", errors="replace")
            for argument in raw_arguments.split(b"\0")
            if argument
        ]
    except OSError:
        arguments = []

    return comm, executable, arguments


def is_obsidian_cli_invocation(arguments: list[str]) -> bool:
    lowered = [argument.lower() for argument in arguments]

    return (
        any(argument.startswith("vault=") for argument in lowered)
        and any(
            argument in CLI_ACTIONS
            or argument.startswith("code=")
            or argument.startswith("id=")
            for argument in lowered[1:]
        )
    )


def obsidian_desktop_running() -> bool:
    """Check for an existing desktop instance without executing Obsidian."""

    try:
        process_paths = list(Path("/proc").iterdir())
    except OSError:
        return False

    for process_path in process_paths:
        if not process_path.name.isdigit():
            continue
        if int(process_path.name) == os.getpid():
            continue
        if not process_belongs_to_current_user(process_path):
            continue

        comm, executable, arguments = process_identity(process_path)
        identity = " ".join([comm, executable, *arguments]).lower()

        if "obsidian" not in identity:
            continue
        if "tasknotes-bridge.py" in identity:
            continue
        if is_obsidian_cli_invocation(arguments):
            continue

        return True

    return False


class ObsidianCLI:
    def __init__(self, executable: str, vault_name: str) -> None:
        self.requested_executable = executable
        self.vault_name = vault_name
        self.executable = self.resolve_executable(executable)

    @staticmethod
    def resolve_executable(executable: str) -> str:
        expanded = str(Path(executable).expanduser())

        if "/" in expanded:
            path = Path(expanded)
            if path.is_file() and os.access(path, os.X_OK):
                return str(path)
            raise CliUnavailable(f"Obsidian CLI is not executable: {path}")

        discovered = shutil.which(expanded)
        if discovered:
            return discovered

        linux_default = Path.home() / ".local" / "bin" / expanded
        if linux_default.is_file() and os.access(linux_default, os.X_OK):
            return str(linux_default)

        raise CliUnavailable(
            "Obsidian CLI was not found. Enable Command line interface in "
            "Obsidian Settings → General."
        )

    def run(
        self,
        arguments: list[str],
        *,
        timeout: float = 20.0,
    ) -> subprocess.CompletedProcess[str]:
        # The official CLI launches the desktop app when no instance exists.
        # QuickShell calls this bridge on a timer, so never execute the CLI
        # unless an Obsidian desktop process is already running.
        if not obsidian_desktop_running():
            raise CliUnavailable(
                "Obsidian is closed. QuickShell will not start it "
                "automatically."
            )

        command = [
            self.executable,
            f"vault={self.vault_name}",
            *arguments,
        ]

        try:
            result = subprocess.run(
                command,
                text=True,
                capture_output=True,
                timeout=timeout,
                check=False,
            )
        except subprocess.TimeoutExpired as error:
            raise CliUnavailable(
                "Obsidian CLI timed out. Ensure Obsidian is running."
            ) from error
        except OSError as error:
            raise CliUnavailable(f"Could not run Obsidian CLI: {error}") from error

        if result.returncode != 0:
            details = (
                result.stderr.strip()
                or result.stdout.strip()
                or f"exit code {result.returncode}"
            )
            raise CliError(f"Obsidian CLI failed: {details}")

        return result

    @staticmethod
    def parse_eval_output(raw_output: str) -> Any:
        candidates = [raw_output.strip()]

        try:
            decoded = json.loads(raw_output)
            if isinstance(decoded, str):
                candidates.insert(0, decoded)
        except json.JSONDecodeError:
            pass

        for candidate in candidates:
            start = candidate.find(CLI_MARKER)
            end = candidate.find(CLI_END_MARKER, start + len(CLI_MARKER))

            if start < 0 or end < 0:
                continue

            payload_text = candidate[start + len(CLI_MARKER) : end]

            try:
                payload = json.loads(payload_text)
            except json.JSONDecodeError as error:
                raise CliError(
                    "Obsidian CLI returned malformed TaskNotes JSON."
                ) from error

            if payload.get("ok") is not True:
                message = text_value(payload.get("error"))
                if "TaskNotes plugin is not loaded" in message:
                    raise CliUnavailable(message)
                raise CliError(message or "TaskNotes CLI evaluation failed.")

            return payload.get("data")

        raise CliError(
            "Obsidian CLI did not return the expected evaluation result."
        )

    def evaluate(
        self,
        body: str,
        *,
        retries: int = 4,
    ) -> Any:
        wrapper = (
            "(async()=>{"
            "try{"
            "const data=await(async()=>{"
            f"{body}"
            "})();"
            f"return {javascript_string(CLI_MARKER)}"
            "+JSON.stringify({ok:true,data})"
            f"+{javascript_string(CLI_END_MARKER)};"
            "}catch(error){"
            f"return {javascript_string(CLI_MARKER)}"
            "+JSON.stringify({ok:false,error:String(error?.stack??error)})"
            f"+{javascript_string(CLI_END_MARKER)};"
            "}"
            "})()"
        )

        last_error: BridgeError | None = None

        for attempt in range(retries):
            try:
                result = self.run(["eval", f"code={wrapper}"])
                return self.parse_eval_output(result.stdout)
            except CliUnavailable as error:
                last_error = error
            except CliError as error:
                if "plugin is not loaded" not in str(error).lower():
                    raise
                last_error = error

            if attempt + 1 < retries:
                time.sleep(1.0)

        raise CliUnavailable(
            str(last_error)
            if last_error
            else "TaskNotes did not become ready in Obsidian."
        )

    def command(self, command_id: str) -> None:
        self.run(["command", f"id={command_id}"])


class TaskNotesVault:
    def __init__(
        self,
        vault_path: str,
        vault_name: str,
        obsidian_bin: str,
    ) -> None:
        self.vault = Path(vault_path).expanduser()

        if not self.vault.exists():
            raise BridgeError(
                f"TaskNotes vault is unavailable: {self.vault}. "
                "Mount the Windows drive and refresh."
            )

        if not self.vault.is_dir():
            raise BridgeError(f"TaskNotes vault path is not a directory: {self.vault}")

        self.vault_name = vault_name or self.vault.name
        self.obsidian_bin = obsidian_bin

        self.settings_path = (
            self.vault / ".obsidian" / "plugins" / "tasknotes" / "data.json"
        )
        self.settings = load_json(self.settings_path)
        self.daily_notes_settings = load_json(
            self.vault / ".obsidian" / "daily-notes.json"
        )

        self.tasks_folder = Path(str(self.settings.get("tasksFolder") or "Tasks"))
        self.archive_folder = Path(
            str(self.settings.get("archiveFolder") or self.tasks_folder / "Archive")
        )
        self.task_root = self.safe_vault_path(self.tasks_folder)
        self.archive_root = self.safe_vault_path(self.archive_folder)

        self.identification_key = str(
            self.settings.get("taskPropertyName") or "type"
        )
        self.identification_value = self.settings.get(
            "taskPropertyValue",
            "task",
        )

        field_mapping = self.settings.get("fieldMapping")
        self.field_mapping = field_mapping if isinstance(field_mapping, dict) else {}

        self.completed_statuses = {
            str(status.get("value"))
            for status in list_value(self.settings.get("customStatuses"))
            if isinstance(status, dict) and status.get("isCompleted") is True
        }
        if not self.completed_statuses:
            self.completed_statuses = {"done"}

        self.completed_status = next(iter(self.completed_statuses))
        self.active_status = str(
            self.settings.get("quickShellDefaultStatus")
            or self.settings.get("defaultTaskStatus")
            or "none"
        )

    def cli(self) -> ObsidianCLI:
        return ObsidianCLI(self.obsidian_bin, self.vault_name)

    @staticmethod
    def plugin_prelude() -> str:
        return (
            'const plugin=app.plugins.getPlugin("tasknotes");'
            'if(!plugin)throw new Error("TaskNotes plugin is not loaded.");'
        )

    def key(self, logical_name: str, fallback: str) -> str:
        value = self.field_mapping.get(logical_name)
        return str(value) if value else fallback

    def safe_vault_path(self, relative_path: Path | str) -> Path:
        candidate = (self.vault / Path(relative_path)).resolve()
        vault_root = self.vault.resolve()

        try:
            candidate.relative_to(vault_root)
        except ValueError as error:
            raise BridgeError("Path escapes the configured vault.") from error

        return candidate

    def task_path(self, task_id: str) -> Path:
        if not task_id:
            raise BridgeError("Task ID is missing.")

        path = self.safe_vault_path(Path(task_id))
        if path.suffix.lower() != ".md":
            raise BridgeError("Task ID must reference a Markdown file.")
        return path

    def is_task(self, metadata: dict[str, Any]) -> bool:
        return metadata.get(self.identification_key) == self.identification_value

    def is_archived(self, path: Path, metadata: dict[str, Any]) -> bool:
        archive_key = self.key("archiveTag", "archived")
        archive_value = metadata.get(archive_key)

        if archive_value is True:
            return True
        if isinstance(archive_value, str) and archive_value.lower() == "true":
            return True

        try:
            path.resolve().relative_to(self.archive_root.resolve())
            return True
        except ValueError:
            return False

    def load_note(self, path: Path) -> tuple[dict[str, Any], str]:
        try:
            text = path.read_text(encoding="utf-8")
        except FileNotFoundError as error:
            raise BridgeError(f"Task file does not exist: {path}") from error
        except OSError as error:
            raise BridgeError(f"Could not read task file {path}: {error}") from error

        metadata, body = split_frontmatter(text)

        if not self.is_task(metadata):
            raise BridgeError(f"File is not a TaskNotes task: {path}")

        return metadata, body

    def save_note(
        self,
        path: Path,
        metadata: dict[str, Any],
        body: str,
    ) -> None:
        modified_key = self.key("dateModified", "dateModified")
        metadata[modified_key] = now_iso()
        atomic_write(path, render_note(metadata, body))

    def task_uri(self, relative_path: str) -> str:
        path_without_suffix = Path(relative_path).with_suffix("")
        return (
            "obsidian://open?"
            f"vault={quote(self.vault_name, safe='')}"
            f"&file={quote(path_without_suffix.as_posix(), safe='/')}"
        )

    def task_record_values(
        self,
        relative_path: str,
        title: str,
        values: dict[str, Any],
    ) -> dict[str, Any]:
        status = text_value(values.get("status") or self.active_status)
        priority = text_value(values.get("priority") or "normal")
        due = text_value(values.get("due"))
        scheduled = text_value(values.get("scheduled"))
        recurrence = text_value(values.get("recurrence"))
        complete_instances = [
            text_value(value)[:10]
            for value in list_value(
                values.get("complete_instances")
                or values.get("completeInstances")
            )
            if text_value(value)
        ]

        today = today_iso()
        recurring_done_today = bool(recurrence) and today in complete_instances
        done = status in self.completed_statuses or recurring_done_today

        date_candidates = [value for value in (scheduled, due) if value]
        next_date = min(date_candidates) if date_candidates else ""

        custom_properties = values.get("customProperties")
        if not isinstance(custom_properties, dict):
            custom_properties = {}

        return {
            "id": relative_path,
            "content": title,
            "done": done,
            "status": status,
            "priority": priority,
            "due": due,
            "scheduled": scheduled,
            "contexts": json_value(list_value(values.get("contexts"))),
            "projects": json_value(list_value(values.get("projects"))),
            "tags": json_value(list_value(values.get("tags"))),
            "recurrence": recurrence,
            "completedDate": text_value(
                values.get("completedDate") or values.get("completed_date")
            ),
            "completeInstances": complete_instances,
            "overdue": bool(due and due[:10] < today and not done),
            "nextDate": next_date,
            "uri": self.task_uri(relative_path),
            "source": text_value(
                values.get("source")
                or custom_properties.get("source")
            ),
        }

    def task_record_file(
        self,
        path: Path,
        metadata: dict[str, Any],
    ) -> dict[str, Any]:
        title_key = self.key("title", "title")
        title = text_value(metadata.get(title_key)).strip() or path.stem
        relative_path = path.relative_to(self.vault).as_posix()
        return self.task_record_values(relative_path, title, metadata)

    def task_record_cli(self, task: dict[str, Any]) -> dict[str, Any]:
        relative_path = text_value(task.get("path") or task.get("id"))
        if not relative_path:
            raise BridgeError("TaskNotes task has no path.")

        title = text_value(task.get("title")).strip() or Path(relative_path).stem
        return self.task_record_values(relative_path, title, task)

    def sort_tasks(self, tasks: list[dict[str, Any]]) -> list[dict[str, Any]]:
        priority_order = {
            "high": 0,
            "normal": 1,
            "low": 2,
            "none": 3,
        }
        tasks.sort(
            key=lambda task: (
                bool(task["done"]),
                task["nextDate"] or "9999-12-31",
                priority_order.get(str(task["priority"]).lower(), 4),
                str(task["content"]).casefold(),
            )
        )
        return tasks

    def list_tasks_cli(self) -> list[dict[str, Any]]:
        body = (
            self.plugin_prelude()
            + "const tasks=await plugin.cacheManager.getAllTasks();"
            + "return {"
            + "tasks,"
            + "completedStatuses:plugin.statusManager.getCompletedStatuses(),"
            + 'activeStatus:plugin.settings.quickShellDefaultStatus'
            + '??plugin.settings.defaultTaskStatus??"none"'
            + "};"
        )
        result = self.cli().evaluate(body)

        if not isinstance(result, dict):
            raise CliError("TaskNotes CLI returned invalid task data.")

        statuses = {
            text_value(value)
            for value in list_value(result.get("completedStatuses"))
            if text_value(value)
        }
        if statuses:
            self.completed_statuses = statuses
            self.completed_status = next(iter(statuses))

        active_status = text_value(result.get("activeStatus"))
        if active_status:
            self.active_status = active_status

        tasks = [
            self.task_record_cli(task)
            for task in list_value(result.get("tasks"))
            if isinstance(task, dict) and task.get("archived") is not True
        ]
        return self.sort_tasks(tasks)

    def list_tasks_files(self) -> list[dict[str, Any]]:
        if not self.task_root.exists():
            return []

        tasks: list[dict[str, Any]] = []

        for path in sorted(self.task_root.rglob("*.md")):
            if not path.is_file():
                continue

            try:
                metadata, _body = split_frontmatter(
                    path.read_text(encoding="utf-8")
                )
            except (BridgeError, OSError, UnicodeError) as error:
                print(
                    f"[TaskNotes bridge] Skipping {path}: {error}",
                    file=sys.stderr,
                )
                continue

            if not self.is_task(metadata):
                continue
            if self.is_archived(path, metadata):
                continue

            tasks.append(self.task_record_file(path, metadata))

        return self.sort_tasks(tasks)

    def list_tasks(self) -> tuple[list[dict[str, Any]], str, bool]:
        try:
            return self.list_tasks_cli(), "obsidian-cli", True
        except CliUnavailable:
            return self.list_tasks_files(), "filesystem", False

    def filename_for_title(self, title: str) -> str:
        sanitized = WINDOWS_INVALID_FILENAME.sub("-", title)
        sanitized = re.sub(r"\s+", " ", sanitized).strip(" .")
        sanitized = sanitized[:180].strip(" .")

        if not sanitized:
            sanitized = dt.datetime.now().strftime("%Y%m%d%H%M%S")

        return sanitized

    def body_template(self, values: dict[str, Any]) -> str:
        defaults = self.settings.get("taskCreationDefaults")
        if not isinstance(defaults, dict) or not defaults.get("useBodyTemplate"):
            return f"# {values['title']}\n"

        template = str(defaults.get("bodyTemplate") or "").strip()
        if not template:
            return f"# {values['title']}\n"

        template_path = self.safe_vault_path(template)
        if template_path.suffix.lower() != ".md":
            template_path = template_path.with_suffix(".md")

        try:
            content = template_path.read_text(encoding="utf-8")
        except FileNotFoundError:
            return f"# {values['title']}\n"

        replacements = {
            "{{title}}": text_value(values.get("title")),
            "{{status}}": text_value(values.get("status")),
            "{{priority}}": text_value(values.get("priority")),
            "{{contexts}}": ", ".join(list_value(values.get("contexts"))),
            "{{tags}}": ", ".join(list_value(values.get("tags"))),
            "{{hashtags}}": " ".join(
                f"#{tag}" for tag in list_value(values.get("tags"))
            ),
            "{{details}}": text_value(values.get("details")),
            "{{date}}": today_iso(),
            "{{time}}": dt.datetime.now().strftime("%H:%M"),
        }

        for token, replacement in replacements.items():
            content = content.replace(token, replacement)

        return content

    def default_scheduled_value(self) -> str:
        defaults = self.settings.get("taskCreationDefaults")
        if not isinstance(defaults, dict):
            return ""

        preset = str(defaults.get("defaultScheduledDate") or "none")
        today = dt.date.today()

        if preset == "today":
            return today.isoformat()
        if preset == "tomorrow":
            return (today + dt.timedelta(days=1)).isoformat()
        if preset in {"next-week", "nextWeek"}:
            return (today + dt.timedelta(days=7)).isoformat()
        return ""

    def add_task_cli(self, title: str) -> dict[str, Any]:
        body = (
            self.plugin_prelude()
            + f"const title={javascript_string(title)};"
            + 'const status=plugin.settings.quickShellDefaultStatus'
            + '??plugin.settings.defaultTaskStatus??"none";'
            + 'const priority=plugin.settings.defaultTaskPriority??"normal";'
            + "const result=await plugin.taskService.createTask({"
            + "title,status,priority,"
            + 'customFrontmatter:{source:"QuickShell"}'
            + "});"
            + "return result.taskInfo;"
        )
        task = self.cli().evaluate(body)
        if not isinstance(task, dict):
            raise CliError("TaskNotes CLI did not return the created task.")
        return self.task_record_cli(task)

    def add_task_files(self, title: str) -> dict[str, Any]:
        self.task_root.mkdir(parents=True, exist_ok=True)

        stem = self.filename_for_title(title)
        path = self.task_root / f"{stem}.md"
        suffix = 2

        while path.exists():
            path = self.task_root / f"{stem}-{suffix}.md"
            suffix += 1

        status_key = self.key("status", "status")
        priority_key = self.key("priority", "priority")
        scheduled_key = self.key("scheduled", "scheduled")
        created_key = self.key("dateCreated", "dateCreated")
        modified_key = self.key("dateModified", "dateModified")

        values = {
            "title": title,
            "status": self.active_status,
            "priority": self.settings.get("defaultTaskPriority") or "normal",
            "contexts": [],
            "tags": [],
            "details": "",
        }

        metadata: dict[str, Any] = {
            self.identification_key: self.identification_value,
            status_key: values["status"],
            priority_key: values["priority"],
            created_key: now_iso(),
            modified_key: now_iso(),
            "source": "QuickShell",
        }

        scheduled = self.default_scheduled_value()
        if scheduled:
            metadata[scheduled_key] = scheduled

        atomic_write(path, render_note(metadata, self.body_template(values)))
        return self.task_record_file(path, metadata)

    def add_task(self, title: str) -> tuple[dict[str, Any], str]:
        title = title.strip()
        if not title:
            raise BridgeError("Task title cannot be empty.")

        try:
            return self.add_task_cli(title), "obsidian-cli"
        except CliUnavailable:
            return self.add_task_files(title), "filesystem"

    def set_done_cli(self, task_id: str, done: bool) -> dict[str, Any]:
        body = (
            self.plugin_prelude()
            + f"const taskId={javascript_string(task_id)};"
            + f"const requestedDone={str(done).lower()};"
            + "let task=await plugin.cacheManager.getTaskInfo(taskId);"
            + 'if(!task)throw new Error("Task not found: "+taskId);'
            + "if(task.recurrence){"
            + "const now=new Date();"
            + "const localDate=[now.getFullYear(),"
            + 'String(now.getMonth()+1).padStart(2,"0"),'
            + 'String(now.getDate()).padStart(2,"0")].join("-");'
            + "const completeInstances=Array.isArray(task.complete_instances)"
            + "?task.complete_instances:[];"
            + "const doneNow=completeInstances.includes(localDate);"
            + "if(doneNow!==requestedDone)"
            + "await plugin.toggleRecurringTaskComplete(task,now);"
            + "}else{"
            + "const doneNow=plugin.statusManager.isCompletedStatus(task.status);"
            + "if(doneNow!==requestedDone){"
            + "const completedStatuses=plugin.statusManager.getCompletedStatuses();"
            + 'const completedStatus=completedStatuses[0]??"done";'
            + 'const activeStatus=plugin.settings.quickShellDefaultStatus'
            + '??plugin.settings.defaultTaskStatus??"none";'
            + "await plugin.updateTaskProperty("
            + 'task,"status",requestedDone?completedStatus:activeStatus);'
            + "}"
            + "}"
            + "task=await plugin.cacheManager.getTaskInfo(taskId)??task;"
            + "return task;"
        )
        task = self.cli().evaluate(body)
        if not isinstance(task, dict):
            raise CliError("TaskNotes CLI did not return the updated task.")
        return self.task_record_cli(task)

    def set_done_files(self, task_id: str, done: bool) -> dict[str, Any]:
        path = self.task_path(task_id)
        metadata, body = self.load_note(path)

        status_key = self.key("status", "status")
        completed_key = self.key("completedDate", "completedDate")
        recurrence_key = self.key("recurrence", "recurrence")
        complete_instances_key = self.key(
            "completeInstances",
            "complete_instances",
        )

        recurrence = text_value(metadata.get(recurrence_key))

        if recurrence:
            complete_instances = [
                text_value(value)[:10]
                for value in list_value(metadata.get(complete_instances_key))
                if text_value(value)
            ]
            today = today_iso()

            if done and today not in complete_instances:
                complete_instances.append(today)
            if not done:
                complete_instances = [
                    value for value in complete_instances if value != today
                ]

            metadata[complete_instances_key] = complete_instances
        else:
            metadata[status_key] = (
                self.completed_status if done else self.active_status
            )
            if done:
                metadata[completed_key] = today_iso()
            else:
                metadata.pop(completed_key, None)

        self.save_note(path, metadata, body)
        return self.task_record_file(path, metadata)

    def set_done(
        self,
        task_id: str,
        done: bool,
    ) -> tuple[dict[str, Any], str]:
        try:
            return self.set_done_cli(task_id, done), "obsidian-cli"
        except CliUnavailable:
            return self.set_done_files(task_id, done), "filesystem"

    def archive_task_cli(self, task_id: str) -> dict[str, Any]:
        body = (
            self.plugin_prelude()
            + f"const taskId={javascript_string(task_id)};"
            + "const task=await plugin.cacheManager.getTaskInfo(taskId);"
            + 'if(!task)throw new Error("Task not found: "+taskId);'
            + "if(task.archived!==true)await plugin.toggleTaskArchive(task);"
            + "return {id:task.path,archived:true,moved:true};"
        )
        result = self.cli().evaluate(body)
        if not isinstance(result, dict):
            raise CliError("TaskNotes CLI did not return the archive result.")
        return result

    def archive_task_files(self, task_id: str) -> dict[str, Any]:
        path = self.task_path(task_id)
        metadata, body = self.load_note(path)

        archive_key = self.key("archiveTag", "archived")
        metadata[archive_key] = True
        self.save_note(path, metadata, body)

        moved = False
        destination = path

        if bool(self.settings.get("moveArchivedTasks", False)):
            try:
                relative_to_tasks = path.relative_to(self.task_root)
            except ValueError:
                relative_to_tasks = Path(path.name)

            destination = self.archive_root / relative_to_tasks
            destination.parent.mkdir(parents=True, exist_ok=True)

            if destination.exists():
                stem = destination.stem
                suffix = destination.suffix
                counter = 2
                while destination.exists():
                    destination = destination.parent / f"{stem}-{counter}{suffix}"
                    counter += 1

            shutil.move(str(path), str(destination))
            moved = True

        return {
            "id": destination.relative_to(self.vault).as_posix(),
            "archived": True,
            "moved": moved,
        }

    def archive_task(self, task_id: str) -> tuple[dict[str, Any], str]:
        try:
            return self.archive_task_cli(task_id), "obsidian-cli"
        except CliUnavailable:
            return self.archive_task_files(task_id), "filesystem"

    def daily_note_path(self, date_value: str) -> Path:
        folder = str(self.daily_notes_settings.get("folder") or "To-Do/Daily")
        return self.safe_vault_path(Path(folder) / f"{date_value}.md")

    def daily_sessions(self, date_value: str) -> list[dict[str, Any]]:
        path = self.daily_note_path(date_value)
        if not path.exists():
            return []

        metadata, _body = split_frontmatter(path.read_text(encoding="utf-8"))
        return [
            json_value(session)
            for session in list_value(metadata.get(self.key("pomodoros", "pomodoros")))
            if isinstance(session, dict)
        ]

    def daily_stats(self, date_value: str) -> dict[str, Any]:
        sessions = self.daily_sessions(date_value)
        work_sessions = [
            session
            for session in sessions
            if text_value(session.get("type")) == "work"
        ]
        completed_work = [
            session
            for session in work_sessions
            if session.get("completed") is True
        ]

        return {
            "date": date_value,
            "path": self.daily_note_path(date_value).relative_to(self.vault).as_posix(),
            "sessions": sessions,
            "sessionCount": len(sessions),
            "pomodorosCompleted": len(completed_work),
            "totalMinutes": round(sum(session_minutes(session) for session in sessions)),
            "workMinutes": round(
                sum(session_minutes(session) for session in work_sessions)
            ),
        }

    def pomodoro_status(self) -> dict[str, Any]:
        daily = self.daily_stats(today_iso())

        body = (
            self.plugin_prelude()
            + "const state=plugin.pomodoroService.getState();"
            + "return {state,settings:{"
            + "workDuration:plugin.settings.pomodoroWorkDuration,"
            + "shortBreakDuration:plugin.settings.pomodoroShortBreakDuration,"
            + "longBreakDuration:plugin.settings.pomodoroLongBreakDuration,"
            + "longBreakInterval:plugin.settings.pomodoroLongBreakInterval,"
            + "storageLocation:plugin.settings.pomodoroStorageLocation"
            + "}};"
        )

        try:
            result = self.cli().evaluate(body)
        except CliUnavailable:
            return {
                "ok": True,
                "cliAvailable": False,
                "cliExecutable": self.obsidian_bin,
                "state": None,
                "settings": {
                    "workDuration": int(
                        self.settings.get("pomodoroWorkDuration") or 25
                    ),
                    "shortBreakDuration": int(
                        self.settings.get("pomodoroShortBreakDuration") or 5
                    ),
                    "longBreakDuration": int(
                        self.settings.get("pomodoroLongBreakDuration") or 15
                    ),
                    "longBreakInterval": int(
                        self.settings.get("pomodoroLongBreakInterval") or 4
                    ),
                    "storageLocation": text_value(
                        self.settings.get("pomodoroStorageLocation")
                    ) or "daily-notes",
                },
                "daily": daily,
            }

        if not isinstance(result, dict) or not isinstance(result.get("state"), dict):
            raise CliError("TaskNotes CLI returned invalid Pomodoro state.")

        state = json_value(result["state"])
        settings = json_value(result.get("settings") or {})

        state["totalPomodoros"] = max(
            int(state.get("totalPomodoros") or 0),
            int(daily["pomodorosCompleted"]),
        )
        state["totalMinutesToday"] = max(
            int(state.get("totalMinutesToday") or 0),
            int(daily["totalMinutes"]),
        )

        return {
            "ok": True,
            "cliAvailable": True,
            "cliExecutable": self.cli().executable,
            "state": state,
            "settings": settings,
            "daily": daily,
        }

    def pomodoro_start(
        self,
        task_id: str,
        duration: int | None,
    ) -> dict[str, Any]:
        duration_js = "undefined" if duration is None else str(duration)
        body = (
            self.plugin_prelude()
            + f"const taskId={javascript_string(task_id)};"
            + f"const duration={duration_js};"
            + "const state=plugin.pomodoroService.getState();"
            + "if(state.currentSession&&!state.isRunning){"
            + "await plugin.pomodoroService.resumePomodoro();"
            + "}else if(state.nextSessionType==='short-break'){"
            + "await plugin.pomodoroService.startBreak(false);"
            + "}else if(state.nextSessionType==='long-break'){"
            + "await plugin.pomodoroService.startBreak(true);"
            + "}else{"
            + "let task=undefined;"
            + "if(taskId){"
            + "task=await plugin.cacheManager.getTaskInfo(taskId);"
            + 'if(!task)throw new Error("Task not found: "+taskId);'
            + "}"
            + "await plugin.pomodoroService.startPomodoro(task,duration);"
            + "}"
            + "return plugin.pomodoroService.getState();"
        )
        state = self.cli().evaluate(body)
        return {
            "ok": True,
            "cliAvailable": True,
            "action": "start",
            "data": json_value(state),
        }

    def pomodoro_command(self, action: str) -> dict[str, Any]:
        cli = self.cli()

        status_body = (
            self.plugin_prelude()
            + "return plugin.pomodoroService.getState();"
        )
        state = cli.evaluate(status_body)
        if not isinstance(state, dict):
            raise CliError("TaskNotes CLI returned invalid Pomodoro state.")

        if action == "pause":
            if state.get("isRunning") is True:
                cli.command("tasknotes:pause-pomodoro")
        elif action == "resume":
            if state.get("currentSession") and state.get("isRunning") is not True:
                cli.command("tasknotes:pause-pomodoro")
        elif action == "stop":
            if state.get("currentSession"):
                cli.command("tasknotes:stop-pomodoro")
        else:
            raise BridgeError(f"Unknown Pomodoro action: {action}")

        refreshed = cli.evaluate(status_body)
        return {
            "ok": True,
            "cliAvailable": True,
            "action": action,
            "data": json_value(refreshed),
        }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="QuickShell bridge for Obsidian TaskNotes through Obsidian CLI."
    )
    parser.add_argument("--vault", required=True)
    parser.add_argument("--vault-name", required=True)
    parser.add_argument("--obsidian-bin", default="obsidian")

    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("list")

    add_parser = subparsers.add_parser("add")
    add_parser.add_argument("--title", required=True)

    done_parser = subparsers.add_parser("set-done")
    done_parser.add_argument("--id", required=True)
    done_parser.add_argument(
        "--done",
        choices=("true", "false"),
        required=True,
    )

    archive_parser = subparsers.add_parser("archive")
    archive_parser.add_argument("--id", required=True)

    subparsers.add_parser("pomodoro-status")

    for action in ("pause", "resume", "stop"):
        subparsers.add_parser(f"pomodoro-{action}")

    pomodoro_start = subparsers.add_parser("pomodoro-start")
    pomodoro_start.add_argument("--task-id", default="")
    pomodoro_start.add_argument("--duration", type=int)

    return parser


def main() -> None:
    arguments = build_parser().parse_args()

    try:
        vault = TaskNotesVault(
            arguments.vault,
            arguments.vault_name,
            arguments.obsidian_bin,
        )

        if arguments.command == "list":
            tasks, backend, cli_available = vault.list_tasks()
            emit(
                {
                    "ok": True,
                    "tasks": tasks,
                    "count": len(tasks),
                    "vault": str(vault.vault),
                    "tasksFolder": vault.tasks_folder.as_posix(),
                    "backend": backend,
                    "cliAvailable": cli_available,
                    "cliExecutable": arguments.obsidian_bin,
                }
            )

        if arguments.command == "add":
            task, backend = vault.add_task(arguments.title)
            emit({"ok": True, "task": task, "backend": backend})

        if arguments.command == "set-done":
            task, backend = vault.set_done(
                arguments.id,
                arguments.done == "true",
            )
            emit({"ok": True, "task": task, "backend": backend})

        if arguments.command == "archive":
            result, backend = vault.archive_task(arguments.id)
            emit({"ok": True, **result, "backend": backend})

        if arguments.command == "pomodoro-status":
            emit(vault.pomodoro_status())

        if arguments.command == "pomodoro-start":
            emit(
                vault.pomodoro_start(
                    arguments.task_id,
                    arguments.duration,
                )
            )

        if arguments.command.startswith("pomodoro-"):
            action = arguments.command.removeprefix("pomodoro-")
            emit(vault.pomodoro_command(action))

        raise BridgeError(f"Unknown command: {arguments.command}")
    except CliUnavailable as error:
        emit(
            {
                "ok": False,
                "cliAvailable": False,
                "error": str(error),
            },
            exit_code=1,
        )
    except BridgeError as error:
        emit({"ok": False, "error": str(error)}, exit_code=1)
    except Exception as error:
        emit(
            {
                "ok": False,
                "error": f"Unexpected TaskNotes bridge error: {error}",
            },
            exit_code=1,
        )


if __name__ == "__main__":
    main()
