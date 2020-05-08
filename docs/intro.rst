Welcome to DependencyManager!
=============================

.. contents::

Introduction
^^^^^^^^^^^^
:cmake:module:`DependencyManager` is a CMake module that facilitates development of super-build projects.
In particular it is designed for constructing software ecosystems, by which we mean
a collection of projects each providing a single solution within a particular field
favoring reliance on other solutions within the ecosystem over external dependencies.
Formation of an ecosystem is an alternative way to structure a single mega-program
by splitting it into individual repositories
and has some key advantages. Firstly, it forces a modular build and
encourages development of user friendly interface with better testing.
More importantly, it encourages more open and collaborative environment.

Projects in an ecosystem should be viewed as part of a single body,
which necessitates that they are developed side by side.
When working on a single project the source code of dependencies has
to be readily available and modifiable without risking loss of work.
The possibility of duplicate dependencies with different and some times
conflicting versions also has to be managed.

:cmake:module:`DependencyManager`  leverages `FetchContent`_ to provide the following features:

- declaration and popluation of dependencies
- placement of dependencies in source
- locking to ensure multiple cmake configurations can run simultaneously without conflict
- management of declared dependency commit hashes for needs of users OR developers (different modes)
- manage version clashes at configure time
- construction of dependency graphs

The Problem
^^^^^^^^^^^^

Dependency structure
--------------------

.. figure:: /_static/example1.png
    :scale: 80%
    :align: center

    Dependency tree of project ``A``.
    Content in ``()`` specifies the version declared by the parent.
    Content in ``[]`` specifies the range of compatible versions.

The above tree shows multiple duplicate entries. Project ``C`` is declared by both ``A`` and ``B``,
but there can't be multiple instances of the same module. We have to choose which version of ``C``
to make available. The two declared nodes ``C`` have different versions. ``B`` was developed using
version 1.0.0, while ``A`` wants some newer features only available from ``1.1.0``.
The most intuitive way to resolve this dependency clash is to give priority to the first declared
version, in this case ``A->C``.

The mechanism for declaring dependencies and deciding which one to make available on population
is implemented in `FetchContent`_. After running the build configuration and resolving dependencies,
we get the following tree.

.. figure:: /_static/full_dependency_tree_clash.png
    :scale: 80%
    :align: center

    Populated dependency tree of project ``A``.
    Content in ``()`` specifies the checked out version.
    Grey arrows point to declared nodes which were not used,
    with dotted arrows showing which nodes were used instead.

The first declared node ``C`` was chosen as expected. However, after checking compatible
version ranges of each duplicate against the checked out version we can
see that node ``E`` that was selected is not compatible with project ``D``.
This could lead to hard to debug errors during compilation, but luckily
:cmake:module:`DependencyManager` stops cmake configuration with an error.
The error can be suppressed by setting ``DEPENDENCYMANAGER_VERSION_ERROR=OFF``,
which allows the above graph of dependency tree to be generated.

From the graph it's clear that the simplest way to resolve this clash
is to reverse the order in which dependencies of ``A`` were declared
and populated.

.. figure:: /_static/full_dependency_tree_no_clash.png
    :scale: 80%
    :align: center

    Populated dependency tree of project ``A`` after reversing order of declaration and population.

Working with dependencies
-------------------------
After running the first configuration and fetching all of dependencies, project ``A`` might have
the following structure:

.. code-block:: text

  A/
  |-- CMakeLists.txt
  |-- dependencies/
  |   |-- CMakeLists.txt
  |   |-- B_SHA1
  |   |-- C_SHA1
  |   |-- D_SHA1
  |   |-- B/
  |   |   |-- ..
  |   |-- C/
  |   |   |-- ..
  |   |-- D/
  |       |-- ..
  |-- src/
  |   |-- CMakeLists.txt
  |   |-- ...
  |-- ...

Files ``<name>_SHA1`` store the commit hash for respective dependencies.

Contents of ``dependencies/CMakeLists.txt`` should include

.. code-block:: cmake

    include(FetchContent)
    FetchContent_Declare(
            dependency_manager
            GIT_REPOSITORY <REPOSITORY_NAME>
            GIT_TAG <COMMIT_TAG>
    )
    FetchContent_MakeAvailable(dependency_manager)
    set(CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH}" PARENT_SCOPE)
    DependencyManager_Declare(B <B_repositoryName> VERSION_RANGE <B_versionRange>)
    DependencyManager_Declare(C <C_repositoryName> VERSION_RANGE <C_versionRange>)
    DependencyManager_Declare(D <D_repositoryName> VERSION_RANGE <D_versionRange>)

This way the DependencyManager module is automatically downloaded without needing pre-installation.
``FetchContent_MakeAvailable()`` includes DependencyManager and sets ``CMAKE_MODULE_PATH``.

To use the targets provided in dependencies they still have to be populated.
For example, ``src/CMakeLists.txt`` could include the following

.. code-block:: cmake

    include(DependencyManager)
    DependencyManager_Populate(B)
    DependencyManager_Populate(C)
    DependencyManager_Populate(D)
    ...

The source code of dependencies is downloaded into ``dependencies/<name>/`` by default.
This can be changed by setting ``DEPENDENCYMANAGER_BASE_DIR`` to a different path.
Contrary to the usual approach in CMake, we do not want dependencies out-of-source
in a build directory. This is because we might want to do some development of dependencies
as well as the main project.

For example, if we found a bug in project ``C`` we might prefer to fix it
within the current workspace. Afterwards, we make a new commit and update it
to version ``1.1.1``. By default, rerunning cmake configuration will
checkout the commit stored in ``C_SHA1`` and get us back to the buggy version.
In this case we can update ``C_SHA1`` with the new hash either by hand or
by setting ``DEPENDENCYMANAGER_HASH_UPDATE`` to ``ON`` and running
cmake configuration which will do it for us.

The default behaviour is to always checkout commit store in ``<name>_SHA1``.
That way when the stored commits are updated after a pull,
running cmake configuraiton will check out the correct version.
This is the behavior that most users will want and expect.

Authors
^^^^^^^
Marat Sibaev and Peter J. Knowles.

.. _FetchContent: https://cmake.org/cmake/help/latest/module/FetchContent.html
