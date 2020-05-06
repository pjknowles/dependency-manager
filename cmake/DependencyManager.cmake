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

    DependencyManager_Declare(<name> <gitRepository> [VERSION_RANGE <versionRange>] [PARENT_NAME <parentName>]
                              [<contentOptions>...])

The :cmake:command:`DependencyManager_Declare()` function is a wrapper over `FetchContent_Declare()`_
with specialised functionality

1. Source code is downloaded into ``${DEPENDENCYMANAGER_BASE_DIR}/<name>``
2. ``STAMP_DIR`` is in source, by default at ``${DEPENDENCYMANAGER_BASE_DIR}/.cmake_stamp_dir``
3. Only Git repositories are supported
4. Commit hash of dependency must be stored in a file ``${name}_SHA1`` in directory from which
   :cmake:command:`DependencyManager_Declare()` is called

The cached variable ``DEPENDENCYMANAGER_BASE_DIR`` is the top level location where source is cloned.
It is set to ``${CMAKE_SOURCE_DIR}/dependencies`` by default and should not be modified in the middle
of the configuration process.

The content ``<name>`` must be supported by `FetchContent_Declare()`_.
For version checking ``<name>`` must be the name given to top level call of ``project()`` in
the dependencies ``CMakeLists.txt``.

``<gitRepository>`` must be a valid ``GIT_REPOSITORY`` as understood by ``ExternalProject_Add``.

The ``<contentOptions>`` can be any of the GIT download or update/patch options
that the ``ExternalProject_Add`` command understands, except for ``GIT_TAG`` and ``GIT_REPOSITORY`` which are
specified separately.

The value of ``GIT_TAG`` passed to ``FetchContent`` must be a commit hash stored in
``${DEPENDENCIES_DIR}/<name>_SHA1`` file.

``<versionRange>`` is a list of compatible versions using comma ``,`` as a separator (NOT semicolon ``;``).
Version must be specified as ``<major>.[<minor>[.<patch>[.<tweak>]]]``
with any missing element assumed zero (consistent with ``VERSION`` comparison operators in ``if()`` statement).
It can be preceded by  relational operators ``<``, ``<=``, ``>``, ``>=`` to specify boundaries of the
range. If no relational operators are given that an exact match is requested.
For example, ``VERSION_RANGE ">=1.2.3,<1.8"`` means from version ``1.2.3`` up to but not including version ``1.8.0``.


Name of the parent node, ``<parentName>``, is needed to construct the dependency tree.
By default it is the name of the most recently called ``project()``, i.e. ``${PROJECT_NAME}``.
In case there are multiple ``project()`` calls parent name can be specified explicitly with option ``PARENT_NAME``.


Populating Dependency
^^^^^^^^^^^^^^^^^^^^^

.. cmake:command:: DependencyManager_Populate

.. code-block:: cmake

    DependencyManager_Populate(<name> [PARENT_NAME <parentName>] [DO_NOT_MAKE_AVAILABLE] [NO_VERSION_ERROR])

This is a again a wrapper over `FetchContent_Populate()`_.
Dependency being populated must have been declared sometime before.

``<name>`` must be the same as in previous call to  :cmake:command:`DependencyManager_Declare()`.

``<parentName>`` is the name of the parent node. By default, it is the last called ``project()``.
It must be the same value as in previous call to  :cmake:command:`DependencyManager_Declare()`.
Even if ``PARENT_NAME`` was not specified during declaration, the default values might differ
if a different ``project()`` call was made at the same scope.

After populating the content ``add_subdirectory()`` is called by default, unless ``DO_NOT_MAKE_AVAILABLE`` is set.

During population stage .
When there are duplicate dependencies ``<versionRange>`` is checked and if an already populated dependency
is outside that range an error is raised during configuration.

If subdirectory gets added, a version check is performed.
Version of a dependency is read from the ``${<name>_VERSION}`` variable which is
automatically set when ``VERSION`` is specified in the ``project()`` call.
If cloned version is not compatible with ``VERSION_RANGE`` specified in :cmake:command:`DependencyManager_Populate()`
than an error gets raised and build configuration stops.
With option ``NO_VERSION_ERROR`` only a warning is printed and configuration continues.
``${name}_VERSION`` is also brought up to ``PARENT_SCOPE``.

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


Graph of Dependency Tree
^^^^^^^^^^^^^^^^^^^^^^^^
.. cmake:command:: DependencyManager_DotGraph

.. code-block:: cmake

    DependencyManager_DotGraph([NAME <name>])

Writes a dot file with the current structure of dependency tree. It can be compiled to a graphics using graphviz.
By default, the dot file is written to ``${CMAKE_CURRENT_BINARY_DIR}/dependencyManager_dotGraph.dot``.
This can be changed by passing ``<name>``, which can be an absolute path or
a path relative to ``${CMAKE_CURRENT_BINARY_DIR}``

(For Developers) Structure of the Dependency Tree
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

To correctly resolve valid versions and provide useful summaries we need to store
the structure of the dependency tree.

Each ``node`` has a unique ``nodeID``, represented with a dot separated list of integers ``i1.i2.i3.i4. ...``,
where ``i1`` is the position of root project (there might be multiple roots at top level),
``i2`` is the position among children of ``i1`` at level 2, etc.
For example ``A->{B->{C}, C->{E}, D->{E}}`` becomes ``1->{1.1->{1.1.1}, 1.2->{1.2.1}, 1.3->{1.3.1}}``

A ``node`` contains the following features:

1. ``NAME`` is name of the project on declaration
2. ``PARENT_NAME`` is name of the parent project on declaration
3. ``CHILDREN`` is an ordered set of nodeID's for its children
4. ``GIT_REPOSITORY`` is the Git url to repository
5. ``GIT_TAG`` is the commit hash stored in relevant ``<name>_SHA1`` file
6. ``VERSION_RANGE`` is the range of required versions

During declaration stage we register each node and add it as a child of a parent node.
If a child node by that name already exists, than its content is overwritten and
a warning about duplicate node gets printed.

By design, nodes that can have children (parent nodes) have a unique name.
Parent nodes are registered when they are first populated and made available.
We keep lists of parent node names, node ID's, and versions.

During population stage, on the first call that makes project available,
we register populated node as a parent.
Version of populated node is extracted from a global property and used to
check that it satisfies ``VERSION_RANGE`` in stored node features.

During declaration stage we populate a list of ``nodeID`` strings and declare
a property under ``nodeID`` name with the relevant node features.
We need to know current nodeID for storage and to increment it.
If we know the parent nodeID we can use the list of declared nodeID's to get all
the relevant children. A sibling with the greatest position is the current nodeID.

During population we update a property with the list of versions for each dependency.

How do we get the parent nodeID?
The dependency tree is reduced to a flat list, so while there are multiple declared nodes
by the same name, population is initiated by a node uniquely identified by its name.
That is, parent nodes form a set.
We need to store their ``nodeID`` as well as their ``VERSION``.

This is the complete definition of declared dependency tree together with the versions
of cloned dependencies. It can be used to check the version and write a graphical
representation of the tree.

Global Properties:

1. ``__DependencyManager_property_nodeIDs`` -- list of nodeID's
2. ``__DependencyManager_property_nodeFeatures_${nodeID}`` -- store node features, one for each node
3. ``__DependencyManager_property_parentNodes`` -- multi-value-arguments
        ``NAME`` - list of parent names,
        ``NODE_ID`` - list of corresponding nodeIDs,
        ``VERSION`` - list of corresponding versions

Useful Operations:

1. ``__DependencyManager_parentNodeID(<parentName> <out>)``
        Return nodeID of node with ``NAME`` <parentName>

2. ``__DependencyManager_childrenNodeIDs(<parentName> <out>)``
        Return nodeID's of all children of project <parentName>

3. ``__DependencyManager_nodeNames(<nodeIDs> <out>)``
        Return a list of node names for corresponding ID's

4. ``__DependencyManager_currentNodeID(<parentName> <name> <out> <duplicate>)``
        Return nodeID for current declaration and whether it is a duplicate,
        in which case nodeID is already registered, nodeFeatures will be overwritten and
        nodeIDs don't need to be updated.

5. ``__DependencyManager_storeNode(<nodeID> <name> <parentName> <versionRange>)``
        Store node features, if nodeID is already registered than update node features with new values and return.
        If not a duplicate, update list of nodeIDs and add itself as a child in parent node features.

6. ``__DependencyManager_updateParentNodes(<nodeID> <name> <parentName> <versionRange>)``
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
    set(SHA1_FILE "${CMAKE_CURRENT_SOURCE_DIR}/${name}_SHA1")
endmacro()

# If there are duplicates in the list, sets ${out} to True
function(__DependencyManager_hasDuplicates list out)
    set(uniqueList "${list}")
    list(REMOVE_DUPLICATES uniqueList)
    list(LENGTH list l1)
    list(LENGTH uniqueList l2)
    if (l1 GREATER l2)
        set(${out} TRUE PARENT_SCOPE)
    else ()
        set(${out} FALSE PARENT_SCOPE)
    endif ()
endfunction()

# Store name, nodeID and version of a new parent node
function(__DependencyManager_updateParentNodes name nodeID version)
    message("__DependencyManager_updateParentNodes(${name} ${nodeID} ${version})")
    set(propertyName __DependencyManager_property_parentNodes)
    get_property(alreadyDefined GLOBAL PROPERTY ${propertyName} DEFINED)
    if (NOT alreadyDefined)
        define_property(GLOBAL PROPERTY ${propertyName}
                BRIEF_DOCS "Stores NAME, NODE_ID and VERSION of each parent node as a multi-value argument"
                FULL_DOCS "Stores NAME, NODE_ID and VERSION of each parent node as a multi-value argument"
                )
    endif ()
    get_property(propertyValue GLOBAL PROPERTY ${propertyName})
    cmake_parse_arguments(prop "" "" "NAME;NODE_ID;VERSION" ${propertyValue})
    set(nameList NAME "${prop_NAME}" "${name}")
    set(nodeIDList NODE_ID "${prop_NODE_ID}" "${nodeID}")
    set(versionList VERSION "${prop_VERSION}" "${version}")
    __DependencyManager_hasDuplicates("${nameList}" dupName)
    __DependencyManager_hasDuplicates("${nodeIDList}" dupID)
    if (dupName OR dupID)
        message(FATAL_ERROR
                "Attempting to add a duplicate parent node: name=${name}, nodeID=${nodeID}, version=${version}")
    endif ()
    set_property(GLOBAL PROPERTY ${propertyName} "${nameList};${nodeIDList};${versionList}")
endfunction()

# makes full content of parentNodes property available at parent scope
function(__DependencyManager_getParentNodes prefix)
    message("__DependencyManager_getParentNodes(${prefix})")
    set(propertyName __DependencyManager_property_parentNodes)
    get_property(alreadyDefined GLOBAL PROPERTY ${propertyName} DEFINED)
    if (NOT alreadyDefined)
        message("!creating parent nodes")
        __DependencyManager_updateParentNodes("${name}" "1" "${CMAKE_PROJECT_VERSION}")
    endif ()
    get_property(propertyValue GLOBAL PROPERTY ${propertyName})
    cmake_parse_arguments("${prefix}" "" "" "NAME;NODE_ID;VERSION" ${propertyValue})
    set(${prefix}_NAME "${${prefix}_NAME}" PARENT_SCOPE)
    set(${prefix}_NODE_ID "${${prefix}_NODE_ID}" PARENT_SCOPE)
    set(${prefix}_VERSION "${${prefix}_VERSION}" PARENT_SCOPE)
endfunction()

# Given a name of the parent returns parent nodeID
# Sets: ${prefix}_nodeID, ${prefix}_version
#TODO generalise to multiple root nodes
function(__DependencyManager_getParentNodeInfo prefix name)
    message("__DependencyManager_getParentNodeInfo(${prefix} ${name}) ")
    __DependencyManager_getParentNodes(prop)
    __DependencyManager_hasDuplicates("${prop_NAME}" dupName)
    if (dupName)
        message("!parent nodes have duplciates")
        message("${prop_NAME}")
        message("${prop_NODE_ID}")
    endif ()
    list(FIND prop_NAME "${name}" i)
    if (i EQUAL -1)
        message(FATAL_ERROR "Searching for a parent node that was not registered: name=${name}")
    endif ()
    list(GET prop_NODE_ID ${i} ${prefix}_nodeID)
    list(GET prop_VERSION ${i} ${prefix}_VERSION)
    set(${prefix}_nodeID "${${prefix}_nodeID}" PARENT_SCOPE)
    set(${prefix}_version "${${prefix}_VERSION}" PARENT_SCOPE)
    #    message("${prefix}_nodeID=${${prefix}_nodeID}")
    #    message("${prefix}_version=${${prefix}_VERSION}")
endfunction()

# return node features
# If nodeID is 1, than this is a root node and it gets created empty on the first call
function(__DependencyManager_getNodeFeatures prefix nodeID)
    message("__DependencyManager_getNodeFeatures(${prefix} ${nodeID})")
    set(propertyName __DependencyManager_property_nodeFeatures_${nodeID})
    get_property(alreadyDefined GLOBAL PROPERTY ${propertyName} DEFINED)
    # create a root node
    if (NOT alreadyDefined)
        if (nodeID EQUAL 1)
            message("creating root node")
            define_property(GLOBAL PROPERTY ${propertyName}
                    BRIEF_DOCS "Stores NAME, PARENT_NAME, CHILDREN, GIT_REPOSITORY, GIT_TAG, VERSION_RANGE of each node"
                    FULL_DOCS "Stores NAME, PARENT_NAME, CHILDREN, GIT_REPOSITORY, GIT_TAG, VERSION_RANGE of each node"
                    )
            set_property(GLOBAL PROPERTY ${propertyName}
                    "NAME;${CMAKE_PROJECT_NAME};PARENT_NAME;;CHILDREN;;GIT_REPOSITORY;;GIT_TAG;;VERSION_RANGE;")
        else ()
            message(FATAL_ERROR "Searching for a node that was not registered: nodeID=${nodeID}")
        endif ()
    endif ()
    get_property(propertyValue GLOBAL PROPERTY ${propertyName})
    cmake_parse_arguments(prop
            "" "NAME;PARENT_NAME;GIT_REPOSITORY;GIT_TAG;VERSION_RANGE"
            "CHILDREN" ${propertyValue})
    set(${prefix}_name "${prop_NAME}" PARENT_SCOPE)
    set(${prefix}_parentName "${prop_PARENT_NAME}" PARENT_SCOPE)
    set(${prefix}_gitRepository "${prop_GIT_REPOSITORY}" PARENT_SCOPE)
    set(${prefix}_gitTag "${prop_GIT_TAG}" PARENT_SCOPE)
    set(${prefix}_versionRange "${prop_VERSION_RANGE}" PARENT_SCOPE)
    set(${prefix}_children "${prop_CHILDREN}" PARENT_SCOPE)
    #    message("${prefix}_name=${prop_NAME}")
    #    message("${prefix}_parentName=${prop_PARENT_NAME}")
    #    message("${prefix}_gitRepository=${prop_GIT_REPOSITORY}")
    #    message("${prefix}_gitTag=${prop_GIT_TAG}")
    #    message("${prefix}_versionRange=${prop_VERSION_RANGE}")
    #    message("${prefix}_children=${prop_CHILDREN}")
endfunction()

# appends a child to a parent node
function(__DependencyManager_addChild parentName child_nodeID)
    message("__DependencyManager_addChild(${parentName} ${child_nodeID})")
    __DependencyManager_getParentNodeInfo(parent ${parentName})
    set(propertyName __DependencyManager_property_nodeFeatures_${parent_nodeID})
    get_property(alreadyDefined GLOBAL PROPERTY ${propertyName} DEFINED)
    if (NOT alreadyDefined)
        message(FATAL_ERROR "Searching for a node that was not registered: nodeID=${parent_nodeID}, name=${parentName}")
    endif ()
    get_property(propertyValue GLOBAL PROPERTY ${propertyName})
    cmake_parse_arguments(prop
            "" "NAME;PARENT_NAME;GIT_REPOSITORY;GIT_TAG;VERSION_RANGE"
            "CHILDREN" ${propertyValue})
    set(property NAME "${prop_NAME}" PARENT_NAME "${prop_PARENT_NAME}" CHILDREN "${prop_CHILDREN};${child_nodeID}"
            GIT_REPOSITORY "${prop_GIT_REPOSITORY}" GIT_TAG "${prop_GIT_TAG}" VERSION_RANGE "${prop_VERSION_RANGE}")
    set_property(GLOBAL PROPERTY ${propertyName} ${property})
endfunction()

# Deduces the current nodeID by looking at the children of parent node
function(__DependencyManager_currentNodeID prefix name parentName)
    message("__DependencyManager_currentNodeID(${prefix} ${name} ${parentName})")
    __DependencyManager_getParentNodeInfo(parent ${parentName})
    __DependencyManager_getNodeFeatures("" "${parent_nodeID}")
    set(duplicate FALSE)
    if (NOT _children)
        set(currentNodeID "${parent_nodeID}.1")
    else ()
        # if any of the children have the same name, use their nodeID and mark them as duplicates
        foreach (id IN LISTS _children)
            __DependencyManager_getNodeFeatures("child" "${id}")
            if (${name} STREQUAL ${child_name})
                set(duplicate TRUE)
                set(currentNodeID "${id}")
                break()
            endif ()
        endforeach ()
        # otherwise increment the last child's nodeID and use it as current
        if (NOT duplicate)
            list(GET _children -1 id)
            string(REPLACE "." ";" idList ${id})
            list(POP_BACK idList i)
            math(EXPR i "${i}+1")
            string(REPLACE ";" "." currentNodeID "${idList};${i}")
        endif ()
    endif ()
    set(${prefix}_duplicate "${duplicate}" PARENT_SCOPE)
    set(${prefix}_nodeID "${currentNodeID}" PARENT_SCOPE)
endfunction()

# Store node features, if nodeID is already registered than update node features with new values and return.
# If not a duplicate, update list of nodeIDs and add itself as a child in parent node features.
function(__DependencyManager_saveNode name parentName gitRepository gitTag versionRange)
    message("__DependencyManager_saveNode(${name} ${parentName} ${gitRepository} ${gitTag} ${versionRange})")
    __DependencyManager_currentNodeID(current ${name} ${parentName})
    set(propertyName __DependencyManager_property_nodeFeatures_${current_nodeID})
    get_property(alreadyDefined GLOBAL PROPERTY ${propertyName} DEFINED)
    if (NOT alreadyDefined)
        define_property(GLOBAL PROPERTY ${propertyName}
                BRIEF_DOCS "Stores NAME, PARENT_NAME, CHILDREN, GIT_REPOSITORY, GIT_TAG, VERSION_RANGE of each node"
                FULL_DOCS "Stores NAME, PARENT_NAME, CHILDREN, GIT_REPOSITORY, GIT_TAG, VERSION_RANGE of each node"
                )
    else ()
        message(STATUS "Saving a duplicate node. Content will be overwritten, name=${name}, nodeID=${current_nodeID}")
    endif ()
    set(property NAME "${name}" PARENT_NAME "${parentName}" CHILDREN "" GIT_REPOSITORY "${gitRepository}"
            GIT_TAG "${gitTag}" VERSION_RANGE "${versionRange}")
    set_property(GLOBAL PROPERTY ${propertyName} ${property})
    if (NOT current_duplicate)
        __DependencyManager_addChild(${parentName} ${current_nodeID})
    endif ()
endfunction()

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
    if (IS_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/${name}")
        find_package(Git REQUIRED)
        execute_process(
                COMMAND "${GIT_EXECUTABLE}" rev-list --max-count=1 HEAD
                WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/${name}"
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
    string(TOLOWER "${name}" lcName)
    __DependencyManager_STAMP_DIR()
    __DependencyManager_SHA1_FILE(${name})
    __DependencyManager_update_SHA1(${name})

    set(options "")
    set(oneValueArgs PARENT_NAME VERSION_RANGE)
    set(multiValueArgs "")
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    if (DEFINED ARG_PARENT_NAME)
        set(parentName "${ARG_PARENT_NAME}")
    else ()
        set(parentName "${PROJECT_NAME}")
    endif ()

    file(STRINGS "${SHA1_FILE}" GIT_TAG)
    string(STRIP "${GIT_TAG}" GIT_TAG)
    message(STATUS
            "Declare dependency: NAME=${name} PARENT_NAME=${parentName} GIT_REPOSITORY=${GIT_REPOSITORY} TAG=${GIT_TAG}")

    __DependencyManager_saveNode(${name} ${parentName} ${GIT_REPOSITORY} "${GIT_TAG}" ${ARG_VERSION_RANGE})

    FetchContent_Declare(
            ${name}

            # List this first so they can be overwritten by our options
            ${ARG_UNPARSED_ARGUMENTS}

            SOURCE_DIR "${DEPENDENCYMANAGER_BASE_DIR}/${name}"
            STAMP_DIR "${STAMP_DIR}"
            GIT_REPOSITORY "${GIT_REPOSITORY}"
            GIT_TAG "${GIT_TAG}"
    )
endfunction()

function(__DependencyManager_VersionCompare version1 comp version2 out)
    if (NOT comp)
        set(comparisonOperator VERSION_EQUAL)
    elseif (comp STREQUAL "=")
        set(comparisonOperator VERSION_EQUAL)
    elseif (comp STREQUAL ">")
        set(comparisonOperator VERSION_GREATER)
    elseif (comp STREQUAL ">=")
        set(comparisonOperator VERSION_GREATER_EQUAL)
    elseif (comp STREQUAL "<")
        set(comparisonOperator VERSION_LESS)
    elseif (comp STREQUAL "<=")
        set(comparisonOperator VERSION_LESS_EQUAL)
    else ()
        message(FATAL_ERROR "Version check failed for ${version1} ${comp} ${version2}")
    endif ()
    if (version1 ${comparisonOperator} version2)
        set(${out} ON PARENT_SCOPE)
    else ()
        set(${out} OFF PARENT_SCOPE)
    endif ()
endfunction()

function(__DependencyManager_VersionCheck versionRange version noError)
    set(compatible ON)
    string(REPLACE "," ";" versionRange "${versionRange}")
    string(STRIP "${version}" version)
    foreach (v IN LISTS versionRange)
        string(STRIP "${v}" v)
        if (NOT v)
            continue()
        endif ()
        string(REGEX MATCH "^[=><]+" comp "${v}")
        string(REGEX REPLACE "^[=><]+" "" v "${v}")
        string(STRIP "${v}" v)
        __DependencyManager_VersionCompare("${version}" "${comp}" "${v}" compatible)
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
    set(oneValueArgs PARENT_NAME)
    set(multiValueArgs "")
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})
    if (DEFINED ARG_NO_VERSION_ERROR)
        set(versionError OFF)
    else ()
        set(versionError ${DEPENDENCYMANAGER_VERSION_ERROR})
    endif ()
    if (DEFINED ARG_PARENT_NAME)
        set(parentName "${ARG_PARENT_NAME}")
    else ()
        set(parentName "${PROJECT_NAME}")
    endif ()
    message("DependencyManager_Populate(${NAME} PARENT_NAME ${ARG_PARENT_NAME})")

    # get nodeID of this node
    __DependencyManager_currentNodeID("" ${name} ${parentName})
    if (NOT _duplicate)
        message(FATAL_ERROR "Populating a node that was not declared before. name=${name}, parentName=${parentName}")
    endif ()

    FetchContent_GetProperties(${name})
    string(TOLOWER "${name}" lcName)
    if (NOT ${lcName}_POPULATED)
        file(LOCK "${lockfile}" GUARD PROCESS TIMEOUT 1000)
        FetchContent_Populate(${name})
        if (NOT ARG_DO_NOT_MAKE_AVAILABLE)
            message(STATUS "DependencyManager_Populate(${name}) and make available")
            set(scopeVersion ${CMAKE_CURRENT_BINARY_DIR}/ScopeVersion_${name}.cmake)
            file(WRITE ${scopeVersion} "set(${name}_VERSION \${${name}_VERSION} PARENT_SCOPE)")
            set(CMAKE_PROJECT_${name}_INCLUDE "${scopeVersion}")
            add_subdirectory(${${lcName}_SOURCE_DIR} ${${lcName}_BINARY_DIR} EXCLUDE_FROM_ALL)
            if (NOT ${name}_VERSION)
                message(STATUS "No version found for project ${name}")
            endif ()
            __DependencyManager_updateParentNodes(${name} ${_nodeID} "${${name}_VERSION}")
        endif ()
        file(LOCK "${lockfile}" RELEASE)
    endif ()

    __DependencyManager_getParentNodeInfo(current ${name})
    if (NOT _nodeID STREQUAL current_nodeID)
        message(FATAL_ERROR "Inconsistent node ID's: _nodeID=${_nodeID}, current_nodeID=${current_nodeID}")
    endif ()
    __DependencyManager_getNodeFeatures(node ${current_nodeID})
    if ((NOT node_name STREQUAL name) OR (NOT node_parentName STREQUAL parentName))
        message(FATAL_ERROR "Corrupt node features or parent node info: node_name(${node_name})!=name(${name}; node_parentName(${node_parentName})!=parentName(${parentName})")
    endif ()

    __DependencyManager_VersionCheck("${node_VersionRange}" "${current_VERSION}" ${versionError})

    set(${name}_VERSION "${current_VERSION}" PARENT_SCOPE)
    foreach (s SOURCE_DIR BINARY_DIR POPULATED)
        set(${lcName}_${s} "${${lcName}_${s}}" PARENT_SCOPE)
    endforeach ()
endfunction()

function(DependencyManager_DotGraph)
    message("DependencyManager_DotGraph")
    cmake_parse_arguments(ARG "" "NAME" "" ${ARGN})
    if (DEFINED ARG_NAME)
        if (IS_ABSOLUTE ${ARG_NAME})
            set(fileName "${ARG_NAME}")
        else ()
            set(fileName "${CMAKE_CURRENT_BINARY_DIR}/${ARG_NAME}")
        endif ()
    else ()
        set(fileName "${CMAKE_CURRENT_BINARY_DIR}/dependencyManager_dotGraph.dot")
    endif ()
    # Loop over each node and write the connection from parent to child
    __DependencyManager_getParentNodes(parent)
    message("parent_NAME=${parent_NAME}")
    message("parent_NODE_ID=${parent_NODE_ID}")
    message("parent_VERSION=${parent_VERSION}")
    set(output "digraph {")
    list(LENGTH parent_NODE_ID n)
    math(EXPR n "${n}-1")
    foreach (i RANGE ${n})
        list(GET parent_NAME ${i} name)
        list(GET parent_NODE_ID ${i} id)
        list(GET parent_VERSION ${i} version)
        __DependencyManager_getNodeFeatures("" "${id}")
        if (i EQUAL 0)
            set(output "${output}\n\"${id}\"[label=\"${name}(${version})\\n\"];")
        endif ()
        foreach (child_id IN LISTS _children)
            __DependencyManager_getNodeFeatures(child "${child_id}")
            list(FIND parent_NAME ${child_name} pos)
            if (NOT pos EQUAL -1)
                list(GET parent_VERSION ${pos} child_version)
                list(GET parent_NODE_ID ${pos} child_as_parent_id)
            endif ()
            set(output "${output}\n\"${child_id}\"[label=\"${child_name}(${child_version})\\n[${child_versionRange}]\"];")
            if (child_id STREQUAL child_as_parent_id)
                set(output "${output}\n\"${id}\"->\"${child_id}\";")
            else ()
                set(output "${output}\n\"${id}\"->\"${child_id}\"[color=blue];")
                set(output "${output}\n\"${id}\"->\"${child_as_parent_id}\"[color=green];")
            endif ()
        endforeach ()
        #set(${prefix}_name "${prop_NAME}" PARENT_SCOPE)
        #set(${prefix}_parentName "${prop_PARENT_NAME}" PARENT_SCOPE)
        #set(${prefix}_gitRepository "${prop_GIT_REPOSITORY}" PARENT_SCOPE)
        #set(${prefix}_gitTag "${prop_GIT_TAG}" PARENT_SCOPE)
        #set(${prefix}_versionRange "${prop_VERSION_RANGE}" PARENT_SCOPE)
        #set(${prefix}_children "${prop_CHILDREN}" PARENT_SCOPE)
    endforeach ()
    # If the child is not a parent then use blue color and add connection to parent of the same name with green color
    # Increment maximum rank of tree
    # For each rank store nodeID's as they come in.
    # They are sorted by construction!
    # To ensure tree structure:
    #   create fictitious rank nodes
    #   add invisible connections among all nodes of the same rank
    set(output "${output}\n}")
    file(WRITE "${fileName}" "${output}")
endfunction()


