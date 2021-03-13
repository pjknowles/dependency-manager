#[=======================================================================[.rst:
DependencyManager
------------------

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

    DependencyManager_Declare(<name> <gitRepository>
                              [VERSION_RANGE <versionRange>]
                              [PARENT_NAME <parentName>]
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
and only specified elements are compared, i.e. ``1.2.3 = 1.2`` is ``TRUE`` where ``1.2`` is the version range.
It can be preceded by  relational operators ``<``, ``<=``, ``>``, ``>=`` to specify boundaries of the
range. If no relational operators are given that an exact match is requested.
For example, ``VERSION_RANGE ">=1.2.3,<1.8"`` means from version ``1.2.3`` up to but not including version ``1.8``.


Name of the parent node, ``<parentName>``, is needed to construct the dependency tree.
By default it is the name of the most recently called ``project()``, i.e. ``${PROJECT_NAME}``.
In case there are multiple ``project()`` calls parent name can be specified explicitly with option ``PARENT_NAME``.


Populating Dependency
^^^^^^^^^^^^^^^^^^^^^

.. cmake:command:: DependencyManager_Populate

.. code-block:: cmake

    DependencyManager_Populate(<name>
                               [PARENT_NAME <parentName>]
                               [DO_NOT_MAKE_AVAILABLE]
                               [NO_VERSION_ERROR])

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

If cached option ``DEPENDENCYMANAGER_VERSION_ERROR`` is set to ``OFF``, then an error
is not raised when version clash is found. Note, that ``NO_VERSION_ERROR`` takes precedence.

If option ``DEPENDENCYMANAGER_FETCHCONTENT`` is set, then everything is implemented using standard
``FetchContent``, instead of dependencies being brought in to ``${DEPENDENCIES_DIR}``

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
#]=======================================================================]

#[=======================================================================[.rst:
[For Developers]
^^^^^^^^^^^^^^^^

Structure of the Dependency Tree
********************************

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

By design, nodes that are made available form a unique set. We call them parent nodes, as they
are the only ones that can declare more dependencies as children.
We track parent nodes and store the following features:

1. ``NAME``
2. ``NODE_ID``
3. ``VERSION`` is the actual version of the project


This is the complete definition of dependency tree .
It is used to check the version and generate its graphical representation.

Global Properties:

1. ``__DependencyManager_property_nodeFeatures_${nodeID}`` -- store node features, one for each node in the full tree
2. ``__DependencyManager_property_nodeList`` -- keeps track of nodes as they are created by storing a list of names and node IDs
        in multi-value-arguements ``NAME`` and ``NODE_ID`` respectively.
3. ``__DependencyManager_property_parentNodes`` -- store extra features of parent nodes in multi-value-arguments:
        ``NAME`` - list of parent names;
        ``NODE_ID`` - list of corresponding nodeIDs;
        ``VERSION`` - list of corresponding versions

Verbose Output
**************
Passing ``--log-level=debug -D DEPENDENCYMANAGER_VERBOSE=ON`` to command-line, turns on
extra printouts. This is useful for debugging only.

Documentation of Utility Functions
**********************************
#]=======================================================================]

# FetchContent has a non-cached variable which means it has to be included every time
include(FetchContent)

include_guard()

set(DEPENDENCYMANAGER_BASE_DIR "${CMAKE_SOURCE_DIR}/dependencies" CACHE PATH
        "Directory in which to clone all dependencies, and where <name>_SHA1 files are stored.")
option(DEPENDENCYMANAGER_HASH_UPDATE
        "If ON, use hash of checked out dependency, else use hash from {NAME}_SHA1 file" OFF)
option(DEPENDENCYMANAGER_VERSION_ERROR
        "If ON, raises an error when incompatible dependency versions are found" ON)
option(DEPENDENCYMANAGER_VERBOSE
        "If ON, adds extra printout during processing. Can be useful for debugging." OFF)
option(DEPENDENCYMANAGER_FETCHCONTENT
        "If ON, FetchContent is used to bring dependencies into the build tree rather than the source tree" OFF)

macro(__DependencyManager_STAMP_DIR)
    set(STAMP_DIR "${DEPENDENCYMANAGER_BASE_DIR}/.cmake_stamp_dir")
endmacro()

macro(__DependencyManager_SHA1_FILE name)
    set(SHA1_FILE "${CMAKE_CURRENT_SOURCE_DIR}/${name}_SHA1")
endmacro()

#[=======================================================================[.rst:
.. code-block:: cmake

    __DependencyManager_hasDuplicates(<list> <out>)

If ``<list>`` contains duplicates, sets variable called ``<out>`` to ``TRUE``,
otherwise to ``FALSE``.
#]=======================================================================]
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

#[=======================================================================[.rst:
.. code-block:: cmake

    __DependencyManager_updateParentNodes(<name> <nodeID> <version>)

Register a node as a parent by adding its parent node features to the global property.
#]=======================================================================]
function(__DependencyManager_updateParentNodes name nodeID version)
    messagev("__DependencyManager_updateParentNodes(${name} ${nodeID} ${version})")
    if (version STREQUAL "")
        set(version "0.0.0")
    endif ()
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

#[=======================================================================[.rst:
.. code-block:: cmake

    __DependencyManager_getParentNodes(<prefix>)

Makes full content of parent nodes property available at parent scope
via lists ``${<prefix>}_NAME``, ``${<prefix>}_NODE_ID``, ``${<prefix>}_VERSION``.
#]=======================================================================]
function(__DependencyManager_getParentNodes prefix)
    messagev("__DependencyManager_getParentNodes(${prefix})")
    set(propertyName __DependencyManager_property_parentNodes)
    get_property(alreadyDefined GLOBAL PROPERTY ${propertyName} DEFINED)
    if (NOT alreadyDefined)
        messagev("!creating parent nodes")
        __DependencyManager_updateParentNodes("${name}" "1" "${CMAKE_PROJECT_VERSION}")
    endif ()
    get_property(propertyValue GLOBAL PROPERTY ${propertyName})
    cmake_parse_arguments("${prefix}" "" "" "NAME;NODE_ID;VERSION" ${propertyValue})
    set(${prefix}_NAME "${${prefix}_NAME}" PARENT_SCOPE)
    set(${prefix}_NODE_ID "${${prefix}_NODE_ID}" PARENT_SCOPE)
    set(${prefix}_VERSION "${${prefix}_VERSION}" PARENT_SCOPE)
endfunction()

#[=======================================================================[.rst:
.. code-block:: cmake

    __DependencyManager_getParentNodeInfo(<prefix> <name>)

Makes parent node features of a parent ``<name>`` available at parent scope
via variables ``${<prefix>}_NODE_ID``, ``${<prefix>}_VERSION``.
#]=======================================================================]
function(__DependencyManager_getParentNodeInfo prefix name)
    messagev("__DependencyManager_getParentNodeInfo(${prefix} ${name}) ")
    __DependencyManager_getParentNodes(prop)
    __DependencyManager_hasDuplicates("${prop_NAME}" dupName)
    __DependencyManager_hasDuplicates("${prop_NODE_ID}" dupID)
    if (dupName OR dupID)
        message(FATAL_ERROR "Parent nodes corrupted, duplicates found: name=${prop_NAME}, nodeID=${prop_NODE_ID}")
    endif ()
    list(FIND prop_NAME "${name}" i)
    if (i EQUAL -1)
        message(FATAL_ERROR "Searching for a parent node that was not registered: name=${name}")
    endif ()
    list(GET prop_NODE_ID ${i} ${prefix}_nodeID)
    list(GET prop_VERSION ${i} ${prefix}_VERSION)
    set(${prefix}_nodeID "${${prefix}_nodeID}" PARENT_SCOPE)
    set(${prefix}_version "${${prefix}_VERSION}" PARENT_SCOPE)
endfunction()

#[=======================================================================[.rst:
.. code-block:: cmake

    __DependencyManager_getNodeFeatures(<prefix> <nodeID>)

Makes node features of a node ``<name>`` available at parent scope via variables
``${prefix}_name``,
``${prefix}_parentName``,
``${prefix}_gitRepository``,
``${prefix}_gitTag``,
``${prefix}_versionRange``,
``${prefix}_children``.
If ``<nodeID>`` is ``1``, than this is a root node and it gets created
empty on the first call
#]=======================================================================]
function(__DependencyManager_getNodeFeatures prefix nodeID)
    messagev("__DependencyManager_getNodeFeatures(${prefix} ${nodeID})")
    set(propertyName __DependencyManager_property_nodeFeatures_${nodeID})
    get_property(alreadyDefined GLOBAL PROPERTY ${propertyName} DEFINED)
    # create a root node
    if (NOT alreadyDefined)
        if (nodeID EQUAL 1)
            messagev("creating root node")
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
endfunction()

#[=======================================================================[.rst:
.. code-block:: cmake

    __DependencyManager_addChild(<parentName> <child_nodeID>)

Appends a child to a parent node.
#]=======================================================================]
function(__DependencyManager_addChild parentName child_nodeID)
    messagev("__DependencyManager_addChild(${parentName} ${child_nodeID})")
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

#[=======================================================================[.rst:
.. code-block:: cmake

    __DependencyManager_currentNodeID(<prefix> <name> <parentName>)

Deduces the current nodeID by looking at the children of the parent node.
Sets the following variables at parent scope:

1. ``${prefix}_duplicate`` to ``TRUE`` if there is already a node under that name among children;
2. ``${prefix}_nodeID`` to deduced current node ID. If the node is a duplicate uses ``nodeID`` of the relevant child.

#]=======================================================================]
function(__DependencyManager_currentNodeID prefix name parentName)
    messagev("__DependencyManager_currentNodeID(${prefix} ${name} ${parentName})")
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

#[=======================================================================[.rst:
.. code-block:: cmake

    __DependencyManager_updateNodeList(<name> <nodeID>)

Updates global list of nodes by storing ``<name>`` and ``<nodeID>``.
#]=======================================================================]
function(__DependencyManager_updateNodeList name nodeID)
    messagev("__DependencyManager_updateNodeList(${name} ${nodeID}) ")
    set(propertyName __DependencyManager_property_nodeList)
    get_property(alreadyDefined GLOBAL PROPERTY ${propertyName} DEFINED)
    if (NOT alreadyDefined)
        define_property(GLOBAL PROPERTY ${propertyName}
                BRIEF_DOCS "Stores NAME, NODE_ID of each node as they are created"
                FULL_DOCS "Stores NAME, NODE_ID of each node as they are created"
                )
    endif ()
    get_property(propertyValue GLOBAL PROPERTY ${propertyName})
    cmake_parse_arguments(prop "" "" "NAME;NODE_ID" ${propertyValue})
    set(property NAME "${prop_NAME}" "${name}" NODE_ID "${prop_NODE_ID}" "${current_nodeID}")
    set_property(GLOBAL PROPERTY ${propertyName} ${property})
endfunction()

#[=======================================================================[.rst:
.. code-block:: cmake

    __DependencyManager_getNodeList(<name> <nodeID>)

Updates global list of nodes by storing ``<name>`` and ``<nodeID>``.
Makes node list available at parent scope via variables ``${<prefix>}_NAME``, ``${<prefix>}_NODE_ID``.
#]=======================================================================]
function(__DependencyManager_getNodeList prefix)
    messagev("__DependencyManager_getNodeList(${prefix})")
    set(propertyName __DependencyManager_property_nodeList)
    get_property(alreadyDefined GLOBAL PROPERTY ${propertyName} DEFINED)
    if (NOT alreadyDefined)
        message(FATAL_ERROR "Attempting to get node list before it was created")
    endif ()
    get_property(propertyValue GLOBAL PROPERTY ${propertyName})
    cmake_parse_arguments("${prefix}" "" "" "NAME;NODE_ID" ${propertyValue})
    set(${prefix}_NAME "${${prefix}_NAME}" PARENT_SCOPE)
    set(${prefix}_NODE_ID "${${prefix}_NODE_ID}" PARENT_SCOPE)
endfunction()

#[=======================================================================[.rst:
.. code-block:: cmake

    __DependencyManager_saveNode(<name> <parentName> <gitRepository> <gitTag> <versionRange>)

Store node features. If the node is a duplicate, overwrite content of the registered node.
Otherwise, create a new node property and add itself as a child of the parent node.
#]=======================================================================]
function(__DependencyManager_saveNode name parentName gitRepository gitTag versionRange)
    messagev("__DependencyManager_saveNode(${name} ${parentName} ${gitRepository} ${gitTag} ${versionRange})")
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
        __DependencyManager_updateNodeList(${name} ${current_nodeID})
    endif ()
endfunction()

#[=======================================================================[.rst:
.. code-block:: cmake

    __DependencyManager_update_SHA1(<name>)

If ``DEPENDENCYMANAGER_HASH_UPDATE`` is ``ON``, than updates ``<name>_SHA1``
of a cloned dependency. The repository and SHA1 file must be in current directory.
#]=======================================================================]
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
            "Declare dependency: NAME=${name} PARENT_NAME=${parentName} GIT_REPOSITORY=${GIT_REPOSITORY} GIT_TAG=${GIT_TAG}")
    messagev("DependencyManager_Declare: DEPENDENCYMANAGER_FETCHCONTENT=${DEPENDENCYMANAGER_FETCHCONTENT}")
    if (DEPENDENCYMANAGER_FETCHCONTENT)
        include(FetchContent)
        FetchContent_Declare(
                ${name}
                ${ARG_UNPARSED_ARGUMENTS}
                GIT_REPOSITORY ${GIT_REPOSITORY}
                GIT_TAG ${GIT_TAG}
        )
        return()
    endif ()

    __DependencyManager_saveNode("${name}" "${parentName}" "${GIT_REPOSITORY}" "${GIT_TAG}" "${ARG_VERSION_RANGE}")

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

#[=======================================================================[.rst:
.. code-block:: cmake

    __DependencyManager_VersionCompare(<version1> <comp> <version2> <out>)

Compares ``<version1>`` and ``<version2>``. ``<comp>`` can be one of
``""``, ``=``, ``<``, ``<=``, ``>``, ``>=``. Empty is equivalent to ``=``.
Comparison operators are mapped to ``VERSION_<COMPARISON>`` options in
``if()`` statements.
If ``<version2>`` has less digits than ``<version1>``,  truncate
``<version1>`` so they are same length.
Result is set to variable ``<out>`` in parent scope.
#]=======================================================================]
function(__DependencyManager_VersionCompare version1 comp version2 out)
    string(REPLACE "." ";" v1 "${version1}")
    string(REPLACE "." ";" v2 "${version2}")
    list(LENGTH v1 n1)
    list(LENGTH v2 n2)
    if (n1 GREATER n2)
        list(SUBLIST v1 0 ${n2} v1)
        list(JOIN v1 "." version1)
    endif ()
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

#[=======================================================================[.rst:
.. code-block:: cmake

    __DependencyManager_VersionCheck(<versionRange> <version> <out>)

Checks that ``<version>`` is within ``<versionRange>``. If it is within, then
store ``TRUE`` in variable ``<out>``, otherwise store ``FALSE``.
#]=======================================================================]
function(__DependencyManager_VersionCheck versionRange version out)
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
    set(${out} "${compatible}" PARENT_SCOPE)
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
    messagev("DependencyManager_Populate(${name} PARENT_NAME ${parentName})")
    messagev("DependencyManager_Populate: DEPENDENCYMANAGER_FETCHCONTENT=${DEPENDENCYMANAGER_FETCHCONTENT}")
    if (DEPENDENCYMANAGER_FETCHCONTENT)
        FetchContent_MakeAvailable(${name})
        return()
    endif ()

    __DependencyManager_getNodeList(all)
    string(TOLOWER "${all_NAME}" all_NAME)
    string(TOLOWER "${name}" lcName)
    list(FIND all_NAME "${lcName}" i)
    if (i EQUAL -1)
        message(FATAL_ERROR "Could not find node name=${name} in the global list of nodes")
    endif ()
    list(GET all_NODE_ID ${i} firstDeclaredNodeID)

    # The node that gets populated is based on Declaration order
    # NOT population order
    # I need to get the node ID using FetchContent properties
    FetchContent_GetProperties(${name})
    if (NOT ${lcName}_POPULATED)
        file(LOCK "${lockfile}" GUARD PROCESS TIMEOUT 1000)
        FetchContent_Populate(${name})
        if (NOT ARG_DO_NOT_MAKE_AVAILABLE)
            message(STATUS "DependencyManager_Populate(${name}) and make available")
            set(scopeVersion ${CMAKE_CURRENT_BINARY_DIR}/UpdateParentNodes_${name}.cmake)
            file(WRITE ${scopeVersion} "__DependencyManager_updateParentNodes(${name} ${firstDeclaredNodeID} \"\${${name}_VERSION}\" )")
            set(CMAKE_PROJECT_${name}_INCLUDE "${scopeVersion}")
            add_subdirectory(${${lcName}_SOURCE_DIR} ${${lcName}_BINARY_DIR})
            if (${name}_VERSION} STREQUAL "")
                set(${name}_VERSION} "0.0.0")
            endif ()
        endif ()
        file(LOCK "${lockfile}" RELEASE)
    endif ()

    __DependencyManager_currentNodeID(current ${name} ${parentName})
    if (NOT current_duplicate)
        message(FATAL_ERROR "Populating a node that was not declared before. name=${name}, parentName=${parentName}")
    endif ()
    __DependencyManager_getParentNodeInfo(first ${name})
    if (NOT firstDeclaredNodeID STREQUAL first_nodeID)
        message(FATAL_ERROR "Inconsistent node ID's: firstDeclaredNodeID=${firstDeclaredNodeID}, first_nodeID=${first_nodeID}")
    endif ()
    __DependencyManager_getNodeFeatures(current ${current_nodeID})
    if ((NOT current_name STREQUAL name) OR (NOT current_parentName STREQUAL parentName))
        message(FATAL_ERROR "Corrupt node features or parent node info: current_name(${current_name})!=name(${name}); current_parentName(${current_parentName})!=parentName(${parentName})")
    endif ()

    __DependencyManager_VersionCheck("${current_versionRange}" "${first_version}" compatible)
    if (NOT compatible)
        set(mess "Cloned version ${name}(${first_version}) is outside of required version range (${current_versionRange})")
        if (versionError)
            message(FATAL_ERROR "${mess}")
        else ()
            message(WARNING "${mess}")
        endif ()
    endif ()

    set(${name}_VERSION "${first_VERSION}" PARENT_SCOPE)
    foreach (s SOURCE_DIR BINARY_DIR POPULATED)
        set(${lcName}_${s} "${${lcName}_${s}}" PARENT_SCOPE)
    endforeach ()
endfunction()

macro(__DependencyManager_nodeLevel id out)
    string(REPLACE "." ";" idList "${id}")
    list(LENGTH idList ${out})
endmacro()

function(DependencyManager_DotGraph)
    messagev("DependencyManager_DotGraph")
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

    set(output "digraph {")
    set(maxLvl 1)
    set(nodeIDs_Lvl1 1)

    __DependencyManager_getParentNodes(parent)
    list(LENGTH parent_NODE_ID n)
    math(EXPR n "${n}-1")
    foreach (i RANGE ${n})
        list(GET parent_NAME ${i} name)
        list(GET parent_NODE_ID ${i} id)
        list(GET parent_VERSION ${i} version)
        __DependencyManager_getNodeFeatures("" "${id}")
        if (i EQUAL 0)
            set(output "${output}\n\"${id}\"[shape=oval,label=\"${name}\\n(${version})\\n\"];")
        endif ()
        foreach (child_id IN LISTS _children)
            __DependencyManager_getNodeFeatures(child "${child_id}")
            list(FIND parent_NAME ${child_name} pos)
            if (NOT pos EQUAL -1)
                list(GET parent_VERSION ${pos} child_version)
                list(GET parent_NODE_ID ${pos} child_as_parent_id)
            endif ()
            __DependencyManager_VersionCheck("${child_versionRange}" "${child_version}" compatible)
            set(color "")
            if (NOT compatible)
                set(color ",color=red")
            endif ()
            set(output "${output}\n\"${child_id}\"[shape=oval${color},label=\"${child_name}\\n(${child_version})\\n[${child_versionRange}]\"];")
            if (child_id STREQUAL child_as_parent_id)
                set(output "${output}\n\"${id}\"->\"${child_id}\";")
            else ()
                set(output "${output}\n\"${id}\"->\"${child_id}\"[color=grey];")
                set(output "${output}\n\"${id}\"->\"${child_as_parent_id}\"[style=dotted];")
            endif ()
            __DependencyManager_nodeLevel("${child_id}" lvl)
            if (lvl GREATER maxLvl)
                set(maxLvl ${lvl})
            endif ()
            list(APPEND nodeIDs_Lvl${lvl} "${child_id}")
        endforeach ()
    endforeach ()
    # To ensure tree structure:
    #   create fictitious rank nodes
    #   add invisible connections among all nodes of the same rank
    foreach (i RANGE 1 ${maxLvl})
        set(output "${output}\nrank${i}[style=invisible,width=0,height=0,fixedsize=true];")
    endforeach ()
    if (${maxLvl} GREATER 1)
        set(output "${output}\nrank1")
        foreach (i RANGE 2 ${maxLvl})
            set(output "${output}->rank${i}")
        endforeach ()
        set(output "${output}[constraint=false,style=invis]")
    endif ()
    foreach (i RANGE 1 ${maxLvl})
        set(output "${output}\n{")
        set(output "${output}rank=same;")
        set(output "${output}\nrank${i}")
        foreach (id IN LISTS nodeIDs_Lvl${i})
            set(output "${output}->\"${id}\"")
        endforeach ()
        set(output "${output}[style=invis];")
        set(output "${output}\nrankdir=LR;")
        set(output "${output}}")
    endforeach ()
    set(output "${output}\n}")
    file(WRITE "${fileName}" "${output}")
endfunction()

macro(messagev arg)
    if (DEPENDENCYMANAGER_VERBOSE)
        message("${arg}")
    endif ()
endmacro()
