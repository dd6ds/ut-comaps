# Qt position plugin "lomiri" (from lomiri-location-service), built against the
# Qt6 that ut-comaps bundles. Ubuntu Touch provides locations only through
# lomiri-location-service; the phone's own plugin is built for the system Qt
# and cannot be loaded by the bundled Qt. This plugin also triggers the
# "allow location access" prompt (trust store) on first use.
cmake_minimum_required(VERSION 3.16)
project(qtposition_lomiri CXX)

set(LLS_SOURCE_DIR "" CACHE PATH "lomiri-location-service source tree")
if(NOT EXISTS "${LLS_SOURCE_DIR}/qt/position/core_geo_position_info_source.cpp")
  message(FATAL_ERROR "LLS_SOURCE_DIR does not point to lomiri-location-service sources")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Threads REQUIRED)
find_package(Qt6 REQUIRED COMPONENTS Core Gui Positioning)
find_package(PkgConfig REQUIRED)
pkg_check_modules(LLS REQUIRED lomiri-location-service)
pkg_check_modules(DBUSCPP REQUIRED dbus-cpp)

set(P "${LLS_SOURCE_DIR}/qt/position")
add_library(qtposition_lomiri MODULE
  ${P}/core_geo_position_info_source.h
  ${P}/core_geo_position_info_source_factory.h
  ${P}/core_geo_position_info_source.cpp
  ${P}/core_geo_position_info_source_factory.cpp
  ${P}/position.qrc
)
target_compile_definitions(qtposition_lomiri PRIVATE QT_NO_KEYWORDS)
target_include_directories(qtposition_lomiri PRIVATE ${P} ${LLS_INCLUDE_DIRS} ${DBUSCPP_INCLUDE_DIRS})
target_link_directories(qtposition_lomiri PRIVATE ${LLS_LIBRARY_DIRS} ${DBUSCPP_LIBRARY_DIRS})
target_link_libraries(qtposition_lomiri PRIVATE
  Threads::Threads Qt6::Core Qt6::Gui Qt6::Positioning ${LLS_LIBRARIES} ${DBUSCPP_LIBRARIES})
