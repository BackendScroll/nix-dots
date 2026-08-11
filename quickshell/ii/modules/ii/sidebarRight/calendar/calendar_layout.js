const weekDays = [
    { day: "Mo", today: 0 },
    { day: "Tu", today: 0 },
    { day: "We", today: 0 },
    { day: "Th", today: 0 },
    { day: "Fr", today: 0 },
    { day: "Sa", today: 0 },
    { day: "Su", today: 0 },
]

function getDateInXMonthsTime(monthShift) {
    const current = new Date()
    return new Date(
        current.getFullYear(),
        current.getMonth() + monthShift,
        1
    )
}

function localDateString(date) {
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day = String(date.getDate()).padStart(2, "0")
    return `${year}-${month}-${day}`
}

function getCalendarLayout(viewingDate, highlightToday) {
    const monthDate = viewingDate || new Date()
    const year = monthDate.getFullYear()
    const month = monthDate.getMonth()
    const firstOfMonth = new Date(year, month, 1)
    const mondayOffset = (firstOfMonth.getDay() + 6) % 7
    const firstCell = new Date(year, month, 1 - mondayOffset)
    const today = new Date()
    const todayString = localDateString(today)

    const calendar = [...Array(6)].map(() => Array(7))

    for (let row = 0; row < 6; row++) {
        for (let column = 0; column < 7; column++) {
            const offset = row * 7 + column
            const date = new Date(
                firstCell.getFullYear(),
                firstCell.getMonth(),
                firstCell.getDate() + offset
            )
            const dateString = localDateString(date)
            const inCurrentMonth =
                date.getFullYear() === year
                && date.getMonth() === month

            calendar[row][column] = {
                day: date.getDate(),
                date: dateString,
                currentMonth: inCurrentMonth,
                today:
                    highlightToday && dateString === todayString
                        ? 1
                        : inCurrentMonth
                            ? 0
                            : -1,
            }
        }
    }

    return calendar
}
