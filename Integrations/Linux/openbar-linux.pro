QT += core gui widgets quick qml quickcontrols2 network dbus svg
CONFIG += c++17 console
CONFIG -= app_bundle
TARGET = openbar-linux
SOURCES += main.cpp DesktopController.cpp
HEADERS += DesktopController.h
RESOURCES += desktop.qrc provider_icons
provider_icons.files = $$files($$PWD/../../Sources/OpenBar/Resources/ProviderIcon-*.svg)
provider_icons.prefix = /logos
provider_icons.base = $$PWD/../../Sources/OpenBar/Resources
QMAKE_CXXFLAGS += -Wall -Wextra
target.path = $$PREFIX/bin
isEmpty(PREFIX): target.path = /usr/local/bin
INSTALLS += target

DESKTOP_VERSION = $$(OPENBAR_DESKTOP_VERSION)
isEmpty(DESKTOP_VERSION): DESKTOP_VERSION = 0.1.0
DEFINES += OPENBAR_DESKTOP_VERSION=\\\"$$DESKTOP_VERSION\\\"
