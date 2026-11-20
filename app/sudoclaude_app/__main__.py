import os
import sys

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine

from .backend import Backend

HERE = os.path.dirname(os.path.abspath(__file__))


def main():
    QGuiApplication.setApplicationName("SudoClaude")
    QGuiApplication.setOrganizationName("SudoClaude")
    QGuiApplication.setDesktopFileName("io.github.splitshotz.SudoClaude")
    app = QGuiApplication(sys.argv)
    icon = os.path.join(HERE, "..", "icon.svg")
    if os.path.exists(icon):
        app.setWindowIcon(QIcon(icon))
    backend = Backend()
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(os.path.join(HERE, "qml", "Main.qml")))
    if not engine.rootObjects():
        return 1
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
