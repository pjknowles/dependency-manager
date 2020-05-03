#[=======================================================================[.rst:
DependencyManager
------------------

.. contents::

.. module:: DependencyManager

Overview
^^^^^^^^

This module facilitates a super-build model for structuring a project as
part of a software ecosystem. It manages a tree of dependencies with possible duplicates
and version clashes.

Declaring Dependency
^^^^^^^^^^^^^^^^^^^^

.. cmake:command:: DependencyManager_Declare

.. code-block:: cmake

    DependencyManager_Declare(<name> <gitRepository> [VERSION <versionRange>...]  [<contentOptions>...])

The :cmake:command:`DependencyManager_Declare()` function is a wrapper over `FetchContent_Declare()`_
with specialised functionality

1. Source code is downloaded into ``${DEPENDENCYMANAGER_BASE_DIR}/<name>``
2. ``STAMP_DIR`` is in source, by default at ``${DEPENDENCYMANAGER_BASE_DIR}/.cmake_stamp_dir``
3. Only Git repositories are supported
4. Commit hash of dependency must be stored in a file ``${DEPENDENCYMANAGER_BASE_DIR}/${name}_SHA1``

The cached variable ``DEPENDENCYMANAGER_BASE_DIR`` is set to ``${CMAKE_SOURCE_DIR}/dependencies`` by default.
It should not be modified in the middle of the configuration process.

The content ``<name>`` must be supported by `FetchContent_Declare()`_.
For version checking ``<name>`` must be the name given to top level call of ``project()`` in
the dependencies ``CMakeLists.txt``.

``<gitRepository>`` must be a valid ``GIT_REPOSITORY`` as understood by ``ExternalProject_Add``.

The ``<contentOptions>`` can be any of the GIT download or update/patch options
that the ``ExternalProject_Add`` command understands, except for ``GIT_TAG`` and ``GIT_REPOSITORY`` which are
specified separately.

The value of ``GIT_TAG`` passed to ``FetchContent`` must be a commit hash stored in
``${DEPENDENCIES_DIR}/<name>_SHA1`` file.

The ``<versionRange>`` specifies a list of compatible versions. Version of a dependency is read from
the ``${<name>_VERSION}`` variable which is automatically set when VERSION is specified in the ``project()`` call.
When there are duplicate dependencies ``<versionRange>`` is checked and if an already populated dependency
is outside that range an error is raised during configuration. Version must be specified as
``<major>.[<minor>[.<patch>[.<tweak>]]]`` preceded by  ``<``, ``<=``, ``>``, ``>=`` to specify boundaries of the
range. If no relational operators are given that an exact match is requested.
A list of version specifications can be passed.
For example, ``>=1.2.3;<1.8`` means from version ``1.2.3`` up to but not including version ``1.8``;
``>1.2.3`` is any version greater than ``1.2.3``; ``<=1.8`` any version up to and including ``1.8``;
and ``1.2.3`` requests an exact match.

Populating Dependency
^^^^^^^^^^^^^^^^^^^^^

.. cmake:command:: DependencyManager_Populate

.. code-block:: cmake

    DependencyManager_Populate(<name> [DO_NOT_MAKE_AVAILABLE] [NO_VERSION_ERROR])

This is a again a wrapper over `FetchContent_Populate()`_.
A call to :cmake:command:`DependencyManager_Declare()` must have been made first.

``<name>`` must be the same as in previous call to  :cmake:command:`DependencyManager_Populate()`.

After populating the content ``add_subdirectory()`` is called by default, unless ``DO_NOT_MAKE_AVAILABLE`` is set.

If subdirectory gets added, a version check is performed. When requested version is not compatible with the
version that took priority at declaration stage (i.e. duplicate dependencies) the default behaviour is for
a ``FATAL_ERROR`` to get raised. If ``NO_VERSION_ERROR`` is set, than a ``WARNING`` is printed instead
and configuration continues.

Note, that file locking is used which acts as a mutex when multiple configurations are run simultaneously.
The file lock files are stored in ``STAMP_DIR``.


Update of Commit Hash
^^^^^^^^^^^^^^^^^^^^^

Every time CMake configuration is rerun an update step is initiated which uses commit hash from ``<name>_SHA1`` file,
checking out the correct version if for some reason a dependency is at a different commit.
Only advanced users with good knowledge of software stack should modify the ``<name>_SHA1`` file.
This applies to developers who in this paradigm need to be able to modify the source code of dependencies
and/or checkout a different commit and successfully configure the build.
Setting cache variable ``DEPENDENCYMANAGER_HASH_UPDATE`` to ON will overwrite ``<name>_SHA1`` file with the
currently checked out hash before the update stage, making sure that the work is preserved.


.. _FetchContent_Declare(): https://cmake.org/cmake/help/latest/module/FetchContent.html#command:fetchcontent_declare
.. _FetchContent_Populate(): https://cmake.org/cmake/help/latest/module/FetchContent.html#command:fetchcontent_populate
#]=======================================================================]

include(FetchContent)

set(DEPENDENCYMANAGER_BASE_DIR "${CMAKE_SOURCE_DIR}/dependencies" CACHE PATH
        "Directory in which to clone all dependencies, and where <name>_SHA1 files are stored.")
option(DEPENDENCYMANAGER_HASH_UPDATE
        "If ON, use hash of checked out dependency, else use hash from {NAME}_SHA1 file" OFF)
option(DEPENDENCYMANAGER_VERSION_ERROR
        "If ON, raises an error when incompatible dependency versions are found" ON)

macro(__DependencyManager_STAMP_DIR)
    set(STAMP_DIR "${DEPENDENCYMANAGER_BASE_DIR}/.cmake_stamp_dir")
endmacro()

macro(__DependencyManager_SHA1_FILE name)
    set(SHA1_FILE "${DEPENDENCYMANAGER_BASE_DIR}/${name}_SHA1")
endmacro()

# Users expect _SHA1 to take priority
#   - if a different version is checked-out,
#     it should check out the stored commit
# Developers expect checked-out dependency to take priority
#   - if a different version is checked-out,
#     it should update the stored commit
function(__DependencyManager_update_SHA1 name)
    if (NOT DEPENDENCYMANAGER_HASH_UPDATE)
        return()
    endif ()
    __DependencyManager_SHA1_FILE(${name})
    if (IS_DIRECTORY "${DEPENDENCYMANAGER_BASE_DIR}/${name}")
        find_package(Git REQUIRED)
        execute_process(
                COMMAND "${GIT_EXECUTABLE}" rev-list --max-count=1 HEAD
                WORKING_DIRECTORY "${DEPENDENCYMANAGER_BASE_DIR}/${name}"
                RESULT_VARIABLE error_code
                OUTPUT_VARIABLE head_sha1
                OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if (error_code)
            message(FATAL_ERROR "Failed to get the hash for HEAD")
        endif ()
        set(GIT_TAG "")
        if (EXISTS "${SHA1_FILE}")
            file(STRINGS "${SHA1_FILE}" GIT_TAG)
        endif ()
        string(STRIP "${GIT_TAG}" GIT_TAG)
        if (NOT "${GIT_TAG}" STREQUAL "${head_sha1}")
            message(STATUS "Updating commit for ${NAME} in file ${SHA1_FILE}")
            file(WRITE "${SHA1_FILE}" ${head_sha1})
        endif ()
    endif ()
endfunction()

function(DependencyManager_Declare name GIT_REPOSITORY)
    __DependencyManager_STAMP_DIR()
    __DependencyManager_SHA1_FILE(${name})
    __DependencyManager_update_SHA1(${name})

    set(options "")
    set(oneValueArgs "")
    set(multiValueArgs VERSION)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    set(_DependencyManager_${PROJECT_NAME}_${name}_VERSION ${ARG_VERSION} CACHE INTERNAL
            "Valid Version range of dependency ${name} for project ${PROJECT_NAME}")

    file(STRINGS "${SHA1_FILE}" GIT_TAG)
    string(STRIP "${GIT_TAG}" GIT_TAG)
    message(STATUS "Declare dependency NAME=${name} GIT_REPOSITORY=${GIT_REPOSITORY} TAG=${GIT_TAG}")

    FetchContent_Declare(
            ${name}
            # List this first so they can be overwritten by our options
            ${ARG_UNPARSED_ARGUMENTS}

            SOURCE_DIR "${DEPENDENCYMANAGER_BASE_DIR}/${name}"
            STAMP_DIR "${STAMP_DIR}"
            GIT_REPOSITORY ${GIT_REPOSITORY}
            GIT_TAG ${GIT_TAG}
    )
endfunction()

function(__DependencyManager_VersionCheck versionRange version noError)
    set(compatible ON)
    string(STRIP "${version}" version)
    foreach (v IN LISTS versionRange)
        string(STRIP "${v}" v)
        if (NOT v)
            continue()
        endif ()
        string(REGEX MATCH "^[=><]+" comp "${v}")
        string(REGEX REPLACE "^[=><]+" "" v "${v}")
        string(STRIP "${v}" v)
        if (NOT comp)
            string(COMPARE EQUAL "${version}" "${v}" compatible)
        elseif (comp STREQUAL "=")
            string(COMPARE EQUAL "${version}" "${v}" compatible)
        elseif (comp STREQUAL ">")
            string(COMPARE GREATER "${version}" "${v}" compatible)
        elseif (comp STREQUAL ">=")
            string(COMPARE GREATER_EQUAL "${version}" "${v}" compatible)
        elseif (comp STREQUAL "<")
            string(COMPARE LESS "${version}" "${v}" compatible)
        elseif (comp STREQUAL "<=")
            string(COMPARE LESS_EQUAL "${version}" "${v}" compatible)
        else ()
            message(FATAL_ERROR "Version check failed for versionCompare=${v} and currentVersion=${version}")
        endif ()
        if (NOT compatible)
            break()
        endif ()
    endforeach ()
    if (NOT compatible)
        set(mess "Current version (${version}) is outside of required version range (${versionRange})")
        if (noError)
            message(WARNING "${mess}")
        else ()
            message(FATAL_ERROR "${mess}")
        endif ()
    endif ()
endfunction()

function(DependencyManager_Populate name)
    __DependencyManager_STAMP_DIR()
    set(lockfile "${STAMP_DIR}/._private_dependencymanager_${name}-lockfile")

    set(options DO_NOT_MAKE_AVAILABLE NO_VERSION_ERROR)
    set(oneValueArgs "")
    set(multiValueArgs "")
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    messagev("DependencyManager_Populate(${name})")
    FetchContent_GetProperties(${name})
    string(TOLOWER "${name}" lcName)
    if (NOT ${lcName}_POPULATED)
        file(LOCK "${lockfile}" GUARD PROCESS TIMEOUT 1000)
        FetchContent_Populate(${name})
        if (NOT ARG_DO_NOT_MAKE_AVAILABLE)
            message("add_subdirectory() for ${name}")
            set(scopeVersion ${CMAKE_CURRENT_BINARY_DIR}/ScopeVersion_${name}.cmake)
            file(WRITE ${scopeVersion} "set(${name}_VERSION \${${name}_VERSION) PARENT_SCOPE")
            set(CMAKE_${name}_INCLUDE "${scopeVersion}")
            add_subdirectory(${${lcName}_SOURCE_DIR} ${${lcName}_BINARY_DIR} EXCLUDE_FROM_ALL)
            __DependencyManager_VersionCheck("${_DependencyManager_${PROJECT_NAME}_${name}_VERSION}" "${name}_VERSION"
                    ${ARG_NO_VERSION_ERROR})
        endif ()
        file(LOCK "${lockfile}" RELEASE)
    endif ()
    foreach (s SOURCE_DIR BINARY_DIR POPULATED)
        set(${lcName}_${s} "${${lcName}_${s}}" PARENT_SCOPE)
    endforeach ()
endfunction()

function(get_dependency_name dep)
    set(_dependency_name _private_dep_${dep} PARENT_SCOPE)
    set(_SHA_file "${_private_dependency_${NAME}_directory}/${dep}_SHA1" PARENT_SCOPE)
endfunction()

function(messagev MESSAGE)
    if (CMAKE_VERSION VERSION_GREATER_EQUAL 3.15)
        message(VERBOSE "${MESSAGE}")
    else ()
        message(STATUS "${MESSAGE}")
    endif ()
endfunction()
