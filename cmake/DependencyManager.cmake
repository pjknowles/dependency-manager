#[=======================================================================[.rst:
DependencyManager
------------------

.. contents::

Overview
^^^^^^^^

This module facilitates a super-build model for structuring a project as
part of a software ecosystem. It manages a tree of dependencies with possible duplicates
and version clashes.

Declaring Dependency
^^^^^^^^^^^^^^^^^^^^

.. command:: DependencyManager_Declare

  .. code-block:: cmake

    DependencyManager_Declare(<name> <gitRepository> [<contentOptions>...] [VERSION <versionRange>] ...)

  The ``DependencyManager_Declare()`` function is a wrapper over ``FetchContent_Declare()``
  with specialised functionality::

  1. Source code is downloaded into ``${DEPENDENCYMANAGER_BASE_DIR}/<name>``
  2. STAMP_DIR is in source, by default at ``${DEPENDENCYMANAGER_BASE_DIR}/.cmake_stamp_dir``
  3. Only GIT repositories are supported
  4. GIT_TAG must be stored in a file ``${DEPENDENCYMANAGER_BASE_DIR}/${name}_SHA1``

  The cached variable ``DEPENDENCYMANAGER_BASE_DIR`` is set to ``${CMAKE_SOURCE_DIR}/dependencies`` by default.
  It should not be modified through out the configuration process.

  The content ``<name>`` must be supported by ``FetchContent_Declare()``.
  For version checking ``<name>`` must be the name given to top level call of ``project()`` in
  the dependencies ``CMakeLists.txt``.

  `<gitRepository>` must be a valid ``GIT_REPOSITORY`` as understood by ``ExternalProject_Add``.

  The ``<contentOptions>`` can be any of the GIT download or update/patch options
  that the ``ExternalProject_Add`` command understands, except for ``GIT_TAG`` and ``GIT_REPOSITORY`` which are
  specified separately.

  The value of ``GIT_TAG`` passed to ``FetchContent`` must be a commit hash stored in
  ``${DEPENDENCIES_DIR}/<name>_SHA1`` file.

  The ``<versionRange>`` specifies a compatible range of versions. Version of a dependency is read from
  the ``${<name>_VERSION}`` variable which is automatically set when VERSION is specified in the ``project()`` call.
  When there are duplicate dependencies ``<versionRange>`` is checked and if an already populated dependency
  is outside that range an error is raised during configuration. Version must be specified as
   ``<major>.[<minor>[.<patch>[.<tweak>]]]`` preceded by  ``<``, ``<=``, ``>``, ``>=`` to specify boundaries of the
   range. If no relational operators are given that an exact match is requested.
   A list of version specifications can be passed, separated by semicolon ``;``.
   For example, ``>=1.2.3;<1.8`` means from version ``1.2.3`` up to but not including version ``1.8``;
   ``>1.2.3`` is any version greater than ``1.2.3``; ``<=1.8`` any version up to and including ``1.8``;
   and ``1.2.3`` requests an exact match.

Populating Dependency
^^^^^^^^^^^^^^^^^^^^^

.. command:: DependencyManager_Populate

  .. code-block:: cmake

    DependencyManager_Populate(<name> [DO_NOT_MAKE_AVAILABLE] [NO_VERSION_ERROR])

  This is a again a wrapper over ``FetchContent_Populate()``.
  A call to :command:`DependencyManager_Populate` must have been made first.

  ``<name>`` must be the same as in previous call to  ``DependencyManager_Populate()``.

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
  Only advanced users with good knowledge of softwrare stack should modify the ``<name>_SHA1`` file.
  This applies to developers who in this paradigm need to be able to modify the source code of dependencies
  and/or checkout a different commit and successfully configure the build.
  Setting cache variable ``DEPENDENCYMANAGER_HASH_UPDATE`` to ON will overwrite ``<name>_SHA1`` file with the
  currently checked out hash before the update stage, making sure that the work is preserved.


#]=======================================================================]

include(FetchContent)

set(DEPENDENCYMANAGER_BASE_DIR "${CMAKE_SOURCE_DIR}/dependencies" CACHE PATH
        "Directory in which to clone all dependencies, and where <name>_SHA1 files are stored.")
option(DEPENDENCYMANAGER_HASH_UPDATE
        "If ON, use commit of checked out dependency, else use commit from {NAME}_SHA1 file" OFF)
option(DEPENDENCYMANAGER_VERSION_ERROR
        "If ON, raises an error when incompatible dependency versions are found" ON)

# Users expect _SHA1 to take priority
#   - if a different version is checked-out,
#     it should check out the stored commit
# Developers expect checked-out dependency to take priority
#   - if a different version is checked-out,
#     it should update the stored commit
# Add an option:
#   LIBCONFIG_UPDATE=ON/OFF
#       - If ON, __DependencyManager_update_SHA1 is called in declared_dependency
#         and the stored SHA1 is overwritten with current commit hash
#         If SHA1 file does not exist already, the commit hash will be written
#       - If OFF, __DependencyManager_update_SHA1 is not called
function(__DependencyManager_update_SHA1 NAME SHA_FILE)
    if (NOT DEPENDENCYMANAGER_HASH_UPDATE)
        return()
    endif ()
    if (IS_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/${NAME}")
        find_package(Git REQUIRED)
        execute_process(
                COMMAND "${GIT_EXECUTABLE}" rev-list --max-count=1 HEAD
                WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/${NAME}"
                RESULT_VARIABLE error_code
                OUTPUT_VARIABLE head_sha
                OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if (error_code)
            message(FATAL_ERROR "Failed to get the hash for HEAD")
        endif ()
        set(GIT_TAG "")
        if (EXISTS "${SHA_FILE}")
            file(STRINGS "${SHA_FILE}" GIT_TAG)
        endif ()
        string(STRIP "${GIT_TAG}" GIT_TAG)
        if (NOT "${GIT_TAG}" STREQUAL "${head_sha}")
            message(STATUS "Updating commit for ${NAME} in file ${SHA_FILE}")
            file(WRITE "${SHA_FILE}" ${head_sha})
        endif ()
    endif ()
endfunction()

# Declare an external git-hosted library on which this project depends
# The first parameter is a character string that will be used to generate file
# and target names, and as a handle for a subsequent get_dependency() call.
# The second parameter is the URL where the git repository can be found.
# The node in the git repository is specified separately in the file
# ${CMAKE_SOURCE_DIR}/dependencies/${NAME}_SHA1
function(DependencyManager_Declare NAME URL)
    set(_private_dependency_${NAME}_directory "${CMAKE_CURRENT_SOURCE_DIR}" CACHE INTERNAL "dependency directory for ${NAME}")
    get_dependency_name(${NAME})
    __DependencyManager_update_SHA1(${NAME} ${_SHA_file})
    file(STRINGS "${_SHA_file}" GIT_TAG)
    message(STATUS "Declare dependency NAME=${NAME} URL=${URL} TAG=${GIT_TAG} DEPENDENCY=${_dependency_name}")
    FetchContent_Declare(
            ${_dependency_name}
            SOURCE_DIR "${CMAKE_SOURCE_DIR}/dependencies/${NAME}"
            STAMP_DIR "${CMAKE_SOURCE_DIR}/dependencies/.cmake_stamp_dir"
            GIT_REPOSITORY ${URL}
            GIT_TAG ${GIT_TAG}
    )
endfunction()

# Load an external git-hosted library on which this project depends.
# The first parameter is the name of the dependency, as passed previously to
# DependencyManager_Declare().
# A second parameter can be given, which if evaluating to true includes the
# library in the cmake build via add_subdirectory(). If omitted, true is assumed.
# lockfile should be in "${DEPENDENCYMANAGER_STAMP_DIR}/._private_dependencymanager_${name}-lockfile"
function(DependencyManager_Populate name)
    get_dependency_name(${name})
    messagev("get_dependency(${name})")
    FetchContent_GetProperties(${_dependency_name})
    if (NOT ${_dependency_name}_POPULATED)
        file(LOCK "${CMAKE_SOURCE_DIR}/dependencies/.${name}_lockfile" GUARD PROCESS TIMEOUT 1000)
        FetchContent_Populate(${_dependency_name})
        if (ARGV1 OR (NOT DEFINED ARGV1))
            message("add_subdirectory() for get_dependency ${name}")
            add_subdirectory(${${_dependency_name}_SOURCE_DIR} ${${_dependency_name}_BINARY_DIR} EXCLUDE_FROM_ALL)
        endif ()
        file(LOCK "${CMAKE_SOURCE_DIR}/dependencies/.${name}_lockfile" RELEASE)
    endif ()
    foreach (s SOURCE_DIR BINARY_DIR POPULATED)
        set(${_dependency_name}_${s} "${${_dependency_name}_${s}}" PARENT_SCOPE)
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
