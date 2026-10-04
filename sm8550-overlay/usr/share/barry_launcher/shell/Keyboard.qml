// Barry Launcher's on-screen keyboard for the AYN Thor's bottom screen.
// barry_launcher_shelld shows it when a text field gets focus (AT-SPI),
// marks this window as a gamescope overlay that leaves key focus on the app
// below, and types what is tapped there through XTest. Covers the screen
// while up: keys (KeyPanel.qml) on the lower (or, for a field in the lower
// half, upper) part; tapping the rest hides it.
// The window stays mapped and hides by opacity, as Steam's overlay does
// (gamescope ignores property changes on unmapped windows).
// It also covers the screen while an app opens ("curtain" in the poll's
// answer: the app's name), hiding its flicker (Firefox resizing itself and
// painting black and grey, Signal's white first frames) until it is ready.
//
// Desktop Mode ("desktop" argument, under KWin; a KWin rule keeps it from
// taking focus): just the keys, along the bottom output's lower edge (KWin's
// script puts it there). It stays mapped there, invisible and click-through
// while hidden: a window mapped anew lands on the screen with the pointer
// first, and would flash on the top screen. Text goes through KWin's input
// method.
import QtQuick
import QtQuick.Window

Window {
    id: win
    title: "Barry Launcher Keyboard"
    flags: Qt.WindowDoesNotAcceptFocus | (desktop && !shown ? Qt.WindowTransparentForInput : 0)
    color: "transparent"
    readonly property bool desktop: Qt.application.arguments.indexOf("desktop") >= 0
    visibility: desktop ? Window.Windowed : Window.FullScreen
    // Window opacity does nothing under Wayland: in Desktop Mode the keys
    // themselves hide, over a transparent window.
    opacity: desktop || shown || covering ? 1 : 0
    width: 1240
    height: desktop ? panel.implicitHeight : 1080

    readonly property string api: "http://127.0.0.1:47824"
    readonly property real s: desktop ? width / 1240 : Math.min(width / 1240, height / 1080)
    property bool shown: false
    property bool atTop: false
    property bool polling: false
    property string curtain: ""  // the app opening under the cover
    property string curtainName: ""  // kept while the cover fades away
    readonly property bool covering: !desktop && (curtain !== "" || coverFade.running)

    function request(method, path, body, callback) {
        const x = new XMLHttpRequest()
        x.onreadystatechange = function () {
            if (x.readyState !== XMLHttpRequest.DONE)
                return
            let obj = null
            if (x.status === 200) {
                try { obj = JSON.parse(x.responseText) } catch (e) { obj = null }
            }
            if (callback)
                callback(obj)
        }
        x.open(method, api + path)
        if (body !== undefined && body !== null) {
            x.setRequestHeader("Content-Type", "application/json")
            x.send(JSON.stringify(body))
        } else {
            x.send()
        }
    }

    function hide() {
        request("POST", "/keyboard", { visible: false })
        win.shown = false
    }

    // Tapping outside the keys hides the keyboard.
    TapHandler {
        enabled: !win.covering
        onTapped: win.hide()
    }

    KeyPanel {
        id: panel
        visible: !win.desktop || win.shown
        autocorrect: true
        width: parent.width
        height: implicitHeight
        y: win.desktop || !win.atTop ? parent.height - height : 0
        s: win.s
        onTyped: function (text) { win.request("POST", "/type", { text: text }) }
        onKey: function (name) { win.request("POST", "/type", { key: name }) }
        onReplace: function (back, text) { win.request("POST", "/type", { back: back, text: text }) }
        onCombo: function (keys) { win.request("POST", "/type", { combo: keys }) }
        onTypedWith: function (body, done) { win.request("POST", "/type", body, function (reply) { if (done) done(reply) }) }
        onHideRequested: win.hide()
    }

    Timer {
        interval: 100
        running: true
        repeat: true
        onTriggered: {
            if (win.polling)
                return
            win.polling = true
            win.request("GET", "/keyboard?h=" + Math.round(panel.height), null, function (st) {
                win.polling = false
                if (!st)
                    return
                win.atTop = st.top
                const c = st.curtain || ""
                if (c !== win.curtain) {
                    if (c !== "")
                        win.curtainName = c
                    else
                        coverFade.restart()
                    win.curtain = c
                }
                if (st.visible && !win.shown) {
                    panel.reset()
                    win.shown = true
                } else if (!st.visible && win.shown) {
                    win.shown = false
                }
            })
        }
    }

    // The cover over an opening app: like the home screen it came
    // from, the app's name and a slow pulse; it fades out once the page is in.
    Rectangle {
        id: cover
        anchors.fill: parent
        visible: win.covering
        color: "black"
        opacity: win.curtain !== "" ? 1 : 0
        NumberAnimation on opacity {
            id: coverFade
            running: false
            from: 1
            to: 0
            duration: 180
        }
        // Touches on it go nowhere (not to the app being made beneath).
        TapHandler {}

        Column {
            anchors.centerIn: parent
            spacing: 28 * win.s
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: win.curtainName
                color: "#eef0f4"
                font { family: "Noto Sans"; pixelSize: 44 * win.s; weight: Font.DemiBold }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 18 * win.s
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        id: dot
                        required property int index
                        width: 16 * win.s
                        height: width
                        radius: width / 2
                        color: "#8a5cf0"
                        opacity: 0.25
                        SequentialAnimation on opacity {
                            running: win.covering
                            loops: Animation.Infinite
                            PauseAnimation { duration: dot.index * 160 }
                            NumberAnimation { to: 1; duration: 320 }
                            NumberAnimation { to: 0.25; duration: 320 }
                            PauseAnimation { duration: (2 - dot.index) * 160 }
                        }
                    }
                }
            }
        }
    }
}
