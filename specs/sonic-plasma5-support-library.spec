%define stable %([ "$(echo %{version} |cut -d. -f2)" -ge 80 -o "$(echo %{version} |cut -d. -f3)" -ge 80 ] && echo -n un; echo -n stable)
%define major %(echo %{version} |cut -d. -f1)
%define weather_ion_major 7

%define libname %mklibname SonicPlasma5Support
%define devname %mklibname SonicPlasma5Support -d

Name: sonic-plasma5-support-library
Version: 6.6.5
Release: 1
URL: https://github.com/Sonic-DE/sonic-plasma5-support-library
Source0: %url/archive/%version/%name-%version.tar.gz
Summary: Support components for porting from Plasma 5 to Plasma 6
License: CC0-1.0 LGPL-2.0+ LGPL-2.1 LGPL-3.0
Group: System/Libraries

BuildSystem: cmake
BuildOption: -DKDE_INSTALL_USE_QT_SYS_PATHS:BOOL=ON
BuildOption: -DBUILD_QCH:BOOL=OFF

BuildRequires: cmake(ECM)
BuildRequires: gettext
BuildRequires: cmake(Qt6)
BuildRequires: cmake(Qt6Core)
BuildRequires: cmake(Qt6Gui)
BuildRequires: cmake(Qt6GuiPrivate)
BuildRequires: cmake(Qt6Quick)
BuildRequires: cmake(Qt6Qml)
BuildRequires: cmake(Qt6Sql)
BuildRequires: cmake(Qt6Widgets)
BuildRequires: cmake(Qt6Network)
BuildRequires: cmake(Qt6DBus)
BuildRequires: cmake(Qt6Test)
BuildRequires: cmake(Qt6QmlTools)
BuildRequires: cmake(KF6Config)
BuildRequires: cmake(KF6CoreAddons)
BuildRequires: cmake(KF6GuiAddons)
BuildRequires: cmake(KF6I18n)
BuildRequires: cmake(KF6Notifications)
BuildRequires: cmake(KF6Solid)
BuildRequires: cmake(KF6Service)
BuildRequires: cmake(KF6IdleTime)
BuildRequires: cmake(KF6KIO)
BuildRequires: cmake(KF6UnitConversion)
BuildRequires: cmake(KF6Holidays)
BuildRequires: cmake(KF6NetworkManagerQt)
BuildRequires: cmake(PlasmaActivities)
BuildRequires: cmake(KF6WindowSystem)
BuildRequires: pkgconfig(x11)
BuildRequires: pkgconfig(xfixes)

Requires: %{libname} = %{EVRD}
Conflicts: plasma5support

%description
Plasma5Support contains migration aids and legacy data engine support for
software that has not fully moved away from Plasma 5 support APIs.

This Sonic package is the local provider for cmake(Plasma5Support), so Sonic
packages do not pull in the stock OpenMandriva Plasma5Support package.

%package -n %{libname}
Summary: Runtime libraries for %{name}
Group: System/Libraries
Requires: %{name} = %{EVRD}
Provides: %{_lib}Plasma5Support = %{EVRD}
Conflicts: %{_lib}Plasma5Support

%description -n %{libname}
Runtime libraries for Plasma5Support compatibility.

%package -n %{devname}
Summary: Development files for %{name}
Group: Development/C
Requires: %{libname} = %{EVRD}
Provides: cmake(Plasma5Support) = %{version}
Provides: %{_lib}Plasma5Support-devel = %{EVRD}
Conflicts: %{_lib}Plasma5Support-devel

%description -n %{devname}
Development headers and CMake files for Plasma5Support compatibility.

%files -f %{name}.lang
%{_datadir}/qlogging-categories6/plasma5support.categories
%{_datadir}/plasma5support
%{_datadir}/plasma/weather_legacy
%{_qtdir}/plugins/plasma5support
%{_qtdir}/qml/org/kde/plasma/plasma5support

%files -n %{libname}
%{_libdir}/libPlasma5Support.so.%{major}*
%{_libdir}/libplasma-geolocation-interface.so.%{major}*
%{_libdir}/libweather_ion.so.%{weather_ion_major}*
%{_libdir}/qt6/metatypes/qt6plasma5support_metatypes.json

%files -n %{devname}
%{_includedir}/Plasma5Support
%{_includedir}/plasma/geolocation
%{_includedir}/plasma5support
%{_libdir}/cmake/Plasma5Support
%{_libdir}/libPlasma5Support.so
%{_libdir}/libplasma-geolocation-interface.so
%{_libdir}/libweather_ion.so
