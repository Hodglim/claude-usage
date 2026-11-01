import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    readonly property int refreshMs: 60 * 1000
    readonly property string script: Qt.resolvedUrl("../code/fetch_usage.py").toString().replace("file://", "")
    readonly property string command: "python3 '" + script + "'"

    property real pct: -1          // 5-hour utilisation, -1 = unknown
    property real resetsAt: 0      // epoch seconds
    property real weekPct: -1
    property real weekResetsAt: 0
    property string errorText: ""
    property bool loading: false
    property real nowSec: Date.now() / 1000
    property real fetchedAt: 0     // epoch seconds of last successful fetch

    readonly property bool hasData: pct >= 0
    // Data older than 15 minutes is shown dimmed
    readonly property bool stale: hasData && fetchedAt > 0 && nowSec - fetchedAt > 15 * 60

    function ago(t) {
        var m = Math.floor(Math.max(0, nowSec - t) / 60)
        return m < 1 ? "just now" : m + " min ago"
    }

    function colorFor(p) {
        if (p < 0) return Kirigami.Theme.disabledTextColor
        if (p < 50) return "#3fb950"
        if (p <= 80) return "#f0883e"
        return "#f85149"
    }

    function countdown(t) {
        if (!t) return ""
        var s = Math.max(0, t - nowSec)
        var h = Math.floor(s / 3600)
        var m = Math.floor((s % 3600) / 60)
        return h > 0 ? h + "h " + m + "m" : m + "m"
    }

    function clockTime(t) {
        return Qt.formatTime(new Date(t * 1000), Qt.locale().timeFormat(Locale.ShortFormat))
    }

    function dayTime(t) {
        return Qt.formatDateTime(new Date(t * 1000), "ddd " + Qt.locale().timeFormat(Locale.ShortFormat))
    }

    function refresh() {
        if (loading) return
        loading = true
        exec.connectSource(command)
    }

    function handle(stdout) {
        loading = false
        var d
        try {
            d = JSON.parse(stdout)
        } catch (e) {
            errorText = "Unexpected output from helper script"
            return
        }
        errorText = d.error || ""
        fetchedAt = d.fetched_at || 0
        if (!d.five_hour) return
        pct = d.five_hour && d.five_hour.utilization !== null ? d.five_hour.utilization : -1
        resetsAt = d.five_hour && d.five_hour.resets_at ? d.five_hour.resets_at : 0
        weekPct = d.seven_day && d.seven_day.utilization !== null ? d.seven_day.utilization : -1
        weekResetsAt = d.seven_day && d.seven_day.resets_at ? d.seven_day.resets_at : 0
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            disconnectSource(sourceName)
            root.handle(data["stdout"])
        }
    }

    Timer {
        interval: root.refreshMs
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    Timer {
        interval: 15 * 1000
        running: true
        repeat: true
        onTriggered: root.nowSec = Date.now() / 1000
    }

    toolTipMainText: hasData ? "Claude session: " + Math.round(pct) + "%" : "Claude usage"
    toolTipSubText: hasData
        ? (resetsAt ? "Resets in " + countdown(resetsAt) + " (" + clockTime(resetsAt) + ")" : "")
          + (weekPct >= 0 ? "\nWeekly: " + Math.round(weekPct) + "%" : "")
        : (errorText || "Loading…")

    compactRepresentation: MouseArea {
        id: compact
        Layout.minimumWidth: root.inTray ? -1 : label.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: Layout.minimumWidth
        hoverEnabled: true
        opacity: root.stale ? 0.5 : 1
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) {
                root.refresh()
            } else {
                root.expanded = !root.expanded
                root.refresh()
            }
        }

        readonly property color fill: root.colorFor(root.hasData ? root.pct : -1)
        readonly property int barHeight: Math.max(3, Math.round(height * 0.18))

        PlasmaComponents.Label {
            id: label
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                bottom: bar.top
                bottomMargin: 1
            }
            text: root.hasData ? Math.round(root.pct) + "%" : "?"
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            font.bold: true
            font.pixelSize: Math.max(8, Math.round(compact.height * 0.5))
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 6
            color: root.hasData ? Kirigami.Theme.textColor : Kirigami.Theme.disabledTextColor
        }

        Rectangle {
            id: bar
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                leftMargin: 1
                rightMargin: 1
                bottomMargin: 1
            }
            height: compact.barHeight
            radius: height / 2
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)

            Rectangle {
                anchors {
                    left: parent.left
                    top: parent.top
                    bottom: parent.bottom
                }
                width: root.hasData ? parent.width * Math.min(100, root.pct) / 100 : 0
                radius: parent.radius
                color: compact.fill
                Behavior on width { NumberAnimation { duration: 400 } }
            }
        }
    }

    // The system tray draws its own heading above expanded applets
    readonly property bool inTray: Plasmoid.containmentDisplayHints & PlasmaCore.Types.ContainmentDrawsPlasmoidHeading

    // One usage block: label + percentage, fill bar, reset line
    component UsageSection: ColumnLayout {
        property string title
        property real value: -1
        property string resetText
        property real size: 1

        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: title
            }
            PlasmaComponents.Label {
                text: value >= 0 ? Math.round(value) + "%" : "–"
                font.bold: true
                font.pixelSize: Kirigami.Theme.defaultFont.pixelSize * 1.6 * size
                color: root.colorFor(value)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Math.round(Kirigami.Units.smallSpacing * 2 * size)
            radius: height / 2
            color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: value >= 0 ? parent.width * Math.min(100, value) / 100 : 0
                radius: parent.radius
                color: root.colorFor(value)
                Behavior on width { NumberAnimation { duration: 400 } }
            }
        }

        PlasmaComponents.Label {
            visible: resetText !== ""
            text: resetText
            opacity: 0.7
            font.pixelSize: size < 1 ? Kirigami.Theme.smallFont.pixelSize : Kirigami.Theme.defaultFont.pixelSize
        }
    }

    fullRepresentation: PlasmaExtras.Representation {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.preferredWidth: Layout.minimumWidth
        Layout.minimumHeight: content.implicitHeight + Kirigami.Units.largeSpacing * 2
                              + (header && header.visible ? header.implicitHeight : 0)
        Layout.preferredHeight: Layout.minimumHeight

        header: PlasmaExtras.PlasmoidHeading {
            visible: !root.inTray
            Kirigami.Heading {
                anchors.fill: parent
                level: 3
                text: "Claude Usage"
            }
        }

        ColumnLayout {
            id: content
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
                margins: Kirigami.Units.largeSpacing
            }
            spacing: Kirigami.Units.largeSpacing

            PlasmaComponents.Label {
                visible: root.errorText !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: root.errorText
                color: Kirigami.Theme.negativeTextColor
            }

            UsageSection {
                title: "5-hour session"
                value: root.pct
                resetText: root.resetsAt > 0
                    ? "Resets in " + root.countdown(root.resetsAt) + "  ·  " + root.clockTime(root.resetsAt)
                    : ""
            }

            UsageSection {
                visible: root.weekPct >= 0
                title: "Weekly"
                value: root.weekPct
                size: 0.75
                resetText: root.weekResetsAt > 0 ? "Resets " + root.dayTime(root.weekResetsAt) : ""
            }

            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents.Label {
                    Layout.fillWidth: true
                    text: root.fetchedAt > 0 ? "Updated " + root.ago(root.fetchedAt) : ""
                    font.pixelSize: Kirigami.Theme.smallFont.pixelSize
                    opacity: 0.5
                }
                PlasmaComponents.ToolButton {
                    icon.name: "view-refresh"
                    enabled: !root.loading
                    onClicked: root.refresh()
                    PlasmaComponents.ToolTip.text: "Refresh now"
                    PlasmaComponents.ToolTip.visible: hovered
                }
            }
        }
    }
}
