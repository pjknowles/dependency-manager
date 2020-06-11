include_guard()
include(CMakeDependentOption)

option(DEPENDENCYMANAGERDOCS_LOCAL
        "If ON, builds local documentation for all projects. Otherwise, download tag files and link to external docs.
        This can be overwritten by setting DEPENDENCYMANAGERDOCS_\${projectName}_LOCAL to a string that would evaluate to True."
        OFF)
set(DEPENDENCYMANAGERDOCS_BASE_DIR "${CMAKE_BINARY_DIR}/docs" CACHE STRING
        "Path to the base directory. Documentation for each project is built under DEPENDENCYMANAGERDOCS_BASE_DIR/<projectName>")

#[=======================================================================[.rst:
DependencyManagerDocs
---------------------

.. module:: DependencyManagerDocs

Overview
^^^^^^^^

This module simplifies building of documentation through doxygen.
Each project has it's own documentation either built locally or hosted online.
Interedependencies are managed through external links using doxygen tag files.

During local build, html documentation for each project is built and tag file is generated.

If using hosted docs, tag files are downloaded and made available for use by higher level projects.


Adding Documentation for a Project
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

.. cmake:command:: DependencyManagerDocs_Add

.. code-block:: cmake

    DependencyManagerDocs_Add(<projectName>
                    [TARGETS <target1> ...]
                    [FILES <extraFiles> ...]
                    [DOXYFILE <doxyfile>]
                    [DOC_URL <docURL>]
                    [TAG_URL <tagURL>]
                    [DEPENDS <dependencyName> ...])

Adds target for building documentation of project with name ``<projectName>``.

``TARGETS`` is followed by a list of targets whose sources and headers should be passed to Doxygen as input.
If no targets are given, than target ``<projectName>`` will be used.

``FILES`` is followed by any extra files that should be passed to Doxygen. For example, README.md from top level.

``DOXYFILE`` is followed by name of the doxyfile configuration file as an absolut path or relative to
``${CMAKE_CURRENT_SOURCE_DIR}``. Defaults to ``Doxyfile``.
The configuration file should have placeholders in-between ``@`` with cmake variable names. Some relevant
CMake variables that are defined can be found below.

``DOC_URL`` is followed by the url to external documentation.
Entries in tag file must be relative to ``<url>``. If <url> is not specified, than the documentation is always built
locally.

``TAG_URL`` is followed by the url to the tag file.
If not specified, it is assumed to be ``<url>/DoxygenTagFiles/<projectName>.tag``.

``DEPENDS`` is followed by a list of projects whose documentation has to be build before current project.
This ensures that tag files of dependencies are available.

.. note:: Top level project (``CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR OR CMAKE_PROJECT_NAME STREQUAL <projectName>``)
   attempts to build local documentation by default.
   This takes precedence over ``DEPENDENCYMANAGERDOCS_LOCAL`` but can be over-ruled by ``DEPENDENCYMANAGERDOCS_<projectName>_LOCAL``.

.. warning:: To ensure tag files of children are available to parent project :cmake:command:`DependencyManagerDocs_Add()`
   should be called as the last step.

Options
*******

``DEPENDENCYMANAGERDOCS_LOCAL``

* If ON, builds local documentation for all projects
* Otherwise, download tag files and link to external docs.
* Default value: ``OFF``.

``DEPENDENCYMANAGERDOCS_<projectName>_LOCAL``

* If evaluates to True, local build of documentation is forced.
* If evaluates to False, tries to use external documentation.
* If not set, it remains empty and not used.
* This takes precedence over ``DEPENDENCYMANAGERDOCS_LOCAL`` and top level directory.
* Default value: ``""``.

``DEPENDENCYMANAGERDOCS_BASE_DIR``

* Path to the base directory. Documentation for each project is built under ``${DEPENDENCYMANAGERDOCS_BASE_DIR}/<projectName>/``
* Default value: ``${CMAKE_BINARY_DIR}/docs``.

Local Variables
***************

Local variables that can be used in <doxyfile> configuration file:

``DEPENDENCYMANAGERDOCS_PROJECT_NAME``

* name of the project, same as ``<projectName>``

``DEPENDENCYMANAGERDOCS_SOURCES``

* list of source files for the INPUT in Doxyfile

``DEPENDENCYMANAGERDOCS_<name>_TAG_FILE`` and  ``DEPENDENCYMANAGERDOCS_<name>_DOC_URL``

* location of tagfile and path to html (either as file path or url) for each project that has been added so far.

``DEPENDENCYMANAGERDOCS_PROJECT_DOC_DIR``

* location where to put projects documentation, default ``${CMAKE_BINARY_DIR}/docs/<projectName>``


Example Doxyfile
****************

Here are example lines that should be in ``<doxyfile>``::

    PROJECT_NAME = @DEPENDENCYMANAGERDOCS_PROJECT_NAME@
    INPUT = @DEPENDENCYMANAGERDOCS_SOURCES@
    TAGFILES = "@DEPENDENCYMANAGERDOCS_<dependencyProjectName>_TAG_FILE@=@DEPENDENCYMANAGERDOCS_<dependencyProjectName>_DOC_URL@"
    GENERATE_TAGFILE = @DEPENDENCYMANAGERDOCS_PROJECT_NAME@.tag

Each dependency should contain a TAGFILES entry, use ``TAGFILES +=`` on a new line to append.



#]=======================================================================]
function(DependencyManagerDocs_Add projectName)
    set(DEPENDENCYMANAGERDOCS_${projectName}_LOCAL "" CACHE STRING
            "Option is checked in cmake if() statement. If evaluates to True, local build of documentation is forced.
If evaluates to False, tries to use external documentation. If not set, it remains empty string and not used.")

    set(options "")
    set(oneValueArgs DOXYFILE DOC_URL TAG_URL)
    set(multiValueArgs TARGETS FILES DEPENDS)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    if (DEFINED ARG_DOXYFILE)
        set(doxyfile ${ARG_DOXYFILE})
    else ()
        set(doxyfile Doxyfile)
    endif ()
    if (NOT DEFINED ARG_TARGETS)
        set(ARG_TARGETS "${projectName}")
    endif ()

    set(local "${DEPENDENCYMANAGERDOCS_LOCAL}")
    if (CMAKE_CURRENT_SOURCE_DIR STREQUAL CMAKE_SOURCE_DIR OR CMAKE_PROJECT_NAME STREQUAL projectName)
        set(local ON)
    endif ()
    if (NOT "${DEPENDENCYMANAGERDOCS_${projectName}_LOCAL}" STREQUAL "")
        if (${DEPENDENCYMANAGERDOCS_${projectName}_LOCAL})
            set(local ON)
        else ()
            set(local OFF)
        endif ()
    endif ()
    if (NOT DEFINED ARG_DOC_URL)
        set(local ON)
    endif ()

    set(DEPENDENCYMANAGERDOCS_PROJECT_DOC_DIR ${DEPENDENCYMANAGERDOCS_BASE_DIR}/${projectName})
    if (NOT TARGET DependencyManagerDocs)
        add_custom_target(DependencyManagerDocs ALL)
    endif ()
    if (local)
        find_package(Doxygen)
        if (DOXYGEN_FOUND)
            set(DEPENDENCYMANAGERDOCS_PROJECT_NAME "${projectName}")
            __DependencyManagerDocs_getSources(DEPENDENCYMANAGERDOCS_SOURCES TARGETS "${ARG_TARGETS}" FILES "${ARG_FILES}")
            __DependencyManagerDocs_getTags()
            configure_file(${CMAKE_CURRENT_SOURCE_DIR}/${doxyfile} ${DEPENDENCYMANAGERDOCS_PROJECT_DOC_DIR}/${doxyfile} @ONLY)
            add_custom_target(${projectName}-doc ALL
                    DEPENDS ${DEPENDENCYMANAGERDOCS_PROJECT_DOC_DIR}/html/index.html
                    )
            add_custom_command(OUTPUT ${DEPENDENCYMANAGERDOCS_PROJECT_DOC_DIR}/html/index.html
                    COMMAND Doxygen::doxygen ${DEPENDENCYMANAGERDOCS_PROJECT_DOC_DIR}/${doxyfile}
                    DEPENDS "${DEPENDENCYMANAGERDOCS_SOURCES_LIST}" ${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt ${DEPENDENCYMANAGERDOCS_PROJECT_DOC_DIR}/${doxyfile}
                    WORKING_DIRECTORY ${DEPENDENCYMANAGERDOCS_PROJECT_DOC_DIR}
                    COMMENT "Generating API documentation with Doxygen for ${projectName} " VERBATIM
                    )
            foreach (child IN LISTS ARG_DEPENDS)
                add_dependencies(${projectName}-doc ${child}-doc)
            endforeach ()
            add_dependencies(DependencyManagerDocs ${projectName}-doc)
            set(tagFile "${DEPENDENCYMANAGERDOCS_PROJECT_DOC_DIR}/${projectName}.tag")
            set(docURL "${DEPENDENCYMANAGERDOCS_PROJECT_DOC_DIR}/html")
        endif (DOXYGEN_FOUND)
    else ()
        if (DEFINED ARG_TAG_URL)
            set(tagURL "${ARG_TAG_URL}")
        else ()
            set(tagURL "${ARG_DOC_URL}/DoxygenTagFiles/${projectName}.tag")
        endif ()
        set(tagFile "${DEPENDENCYMANAGERDOCS_PROJECT_DOC_DIR}/${projectName}.tag")
        # download tag file
        file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/DownloadTagFile.cmake "file(DOWNLOAD \"${tagURL}\" \"${tagFile}\")")
        file(DOWNLOAD "${tagURL}" "${tagFile}")
        add_custom_target(${projectName}-doc ALL DEPENDS ${tagFile})
        add_custom_command(OUTPUT ${tagFile}
                COMMAND ${CMAKE_COMMAND} -P  ${CMAKE_CURRENT_BINARY_DIR}/DownloadTagFile.cmake
                DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/DownloadTagFile.cmake ${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt
                WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
                COMMENT "Downloading tag file for ${projectName} " VERBATIM
                )
        add_dependencies(DependencyManagerDocs ${projectName}-doc)
        set(docURL "${ARG_DOC_URL}")
    endif ()
    __DependencyManagerDocs_appendTags(${projectName} "${tagFile}" "${docURL}")
endfunction()

macro(__DependencyManagerDocs_appendAbs dir file out)
    set(f "${file}")
    if (NOT IS_ABSOLUTE "${file}")
        set(f "${dir}/${file}")
    endif ()
    set(${out} "${${out}} ${f}")
    list(APPEND ${out}_LIST "${f}")
endmacro()

#[=========================================================[
Create a list of sources using sources and headers from each target and a passed list of files.
Return list of sources as absolute paths.
#]=========================================================]
function(__DependencyManagerDocs_getSources out)
    set(options "")
    set(oneValueArgs "")
    set(multiValueArgs TARGETS FILES)
    cmake_parse_arguments("" "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    set(${out} "")
    foreach (target IN LISTS _TARGETS)
        if (NOT TARGET ${target})
            continue()
        endif ()
        get_target_property(pub_head ${target} PUBLIC_HEADER)
        get_target_property(priv_head ${target} PRIVATE_HEADER)
        get_target_property(sources ${target} SOURCES)
        if(NOT pub_head)
            set(pub_head "")
        endif()
        if(NOT priv_head)
            set(priv_head "")
        endif()
        if(NOT sources)
            set(sources "")
        endif()
        get_target_property(dir ${target} SOURCE_DIR)
        foreach (file IN LISTS pub_head priv_head sources)
            __DependencyManagerDocs_appendAbs("${dir}" "${file}" ${out})
        endforeach ()
    endforeach ()
    foreach (file IN LISTS _FILES)
        __DependencyManagerDocs_appendAbs("${CMAKE_CURRENT_SOURCE_DIR}" "${file}" ${out})
    endforeach ()
    set(${out} "${${out}}" PARENT_SCOPE)
    set(${out}_LIST "${${out}_LIST}" PARENT_SCOPE)
endfunction()

#[=========================================================[
#]=========================================================]
function(__DependencyManagerDocs_appendTags name file url)
    set(propertyName __DependencyManagerDocs_property_tagfiles)
    get_property(alreadyDefined GLOBAL PROPERTY ${propertyName} DEFINED)
    if (NOT alreadyDefined)
        define_property(GLOBAL PROPERTY ${propertyName}
                BRIEF_DOCS "stores NAME, TAG_FILE and DOC_URL for each project as multi-value arguments"
                FULL_DOCS "stores NAME, TAG_FILE and DOC_URL for each project as multi-value arguments"
                )
    endif ()
    get_property(propertyValue GLOBAL PROPERTY ${propertyName})
    cmake_parse_arguments("" "" "" "NAME;TAG_FILE;DOC_URL" ${propertyValue})
    list(APPEND _NAME "${name}")
    list(APPEND _TAG_FILE "${file}")
    list(APPEND _DOC_URL "${url}")
    set_property(GLOBAL PROPERTY ${propertyName} "NAME;${_NAME};TAG_FILE;${_TAG_FILE};DOC_URL;${_DOC_URL}")
endfunction()

function(__DependencyManagerDocs_getTags)
    set(propertyName __DependencyManagerDocs_property_tagfiles)
    get_property(alreadyDefined GLOBAL PROPERTY ${propertyName} DEFINED)
    if (NOT alreadyDefined)
        return()
    endif ()
    get_property(propertyValue GLOBAL PROPERTY ${propertyName})
    cmake_parse_arguments("" "" "" "NAME;TAG_FILE;DOC_URL" ${propertyValue})
    list(LENGTH _NAME n)
    math(EXPR n "${n}-1")
    foreach (i RANGE "${n}")
        list(GET _NAME ${i} name)
        list(GET _TAG_FILE ${i} file)
        list(GET _DOC_URL ${i} url)
        set(DEPENDENCYMANAGERDOCS_${name}_TAG_FILE "${file}" PARENT_SCOPE)
        set(DEPENDENCYMANAGERDOCS_${name}_DOC_URL "${url}" PARENT_SCOPE)
    endforeach ()
endfunction()
