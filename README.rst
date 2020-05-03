DependencyManager
------------------


Introduction and Motivation
^^^^^^^^^^^^^^^^^^^^^^^^^^^

Consider a project with a few dependency packages, which themselves have a few more dependencies and so on,
forming a large dependency tree.
Some nodes in that dependency tree will be duplicates.
Some duplicate will have different versions.

For example::

    A <- {B(v1.0) <- {C(v1.1), D(v1.0)},
          C(v1.0) <- {E(v1.0)},
          D(v1.0) <- {E(v1.1)}}

where {} encapsulate a list of dependencies.

The goal is to obtain all of the dependencies in a single top level directory
without duplication and honoring the versions specified at the top level.

CMake has a native module that can achieve just that,
`FetchContent <https://cmake.org/cmake/help/latest/module/FetchContent.html>`_.
By declaring all dependencies with ``FetchContent_Declare``, and using consistent names,
there is only one instance of each dependency. The first one that gets declared
sets the version, which guarantees that top level versions are preferred as
long as all of dependencies are declared before any of them are populated.
As each of the top dependencies are populated, the branch is traversed all the way
to the leaves in order of declaration.
This defines how conflicting versions for lower level dependencies are resolved

In the above example a flat list of dependencies will look like this::

    A <- {B(v1.0), C(v1.0), D(v1.0), E(v1.0)}

Our objective is to implement a super-build, where most of the dependencies are
part of the same software ecosystem.
They are developed in tandem with the current project and developers
need to be able to modify their source code.
Any modifications should be preserved so that they can be committed and pushed
without transitioning to a different workspace.

``DependencyManager`` facilitates our super-build model by providing the following
functionality:

- declaration and population of dependencies by leveraging ``FetchContent``
- placement of dependencies outside of build directory, in source
- locking to ensure multiple cmake configurations can run simultaneously without conflict
- management of declared dependency commit hashes for needs of users OR developers (different modes)
- manage version clashes at configure time

