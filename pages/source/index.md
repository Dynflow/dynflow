---
layout: page
title: About
skip-title: true
sharing: true
---

<div id="big_logo" class="well"><img src="/images/logo-long.png"></div>

Dynflow (**DYN**amic work**FLOW**) is a workflow engine
written in Ruby that allows to:

-   Keep track of the progress of running processes
-   Run the code asynchronously
-   When something goes wrong, pause the process, optionally let user interact, resume the process, skip some steps when needed
-   Detect independent parts and run them concurrently
-   Compose simple actions into more complex scenarios
-   Extend the workflows from third-party libraries
-   Keep consistency between local transactional database and
    external services
-   Suspend the long-running steps, not blocking the thread pool
-   Cancel steps when possible
-   Extend the actions behavior with middlewares
-   Pick different adapters to provide: storage backend, transactions, or executor implementation

Dynflow has been developed to be able to support orchestration of services in the
[Katello](http://katello.org) and [Foreman](http://theforeman.org/) projects.

### Planned features

-   Define the input/output interface between the building blocks
-   Define rollback for the workflow
-   Have multiple workers for distributing the load (in progress)
-   Migration to [concurrent-ruby](http://concurrent-ruby.com) (in progress)

## Getting started

### Requirements

-   Ruby MRI 1.9.3, 2.0, or 2.1.
-   JRuby and Rubinius support is on the way.

### Installation

`gem install dynflow`

*TODO*

## Links

-   [Github](https://github.com/dynflow/dynflow)

## Current status

![](https://img.shields.io/travis/Dynflow/dynflow/master.svg?style=flat)
![](https://img.shields.io/github/issues/Dynflow/dynflow.svg?style=flat)
![](https://img.shields.io/gem/v/dynflow.svg?style=flat)
![](https://img.shields.io/badge/license-MIT-brightgreen.svg?style=flat)

## Authors

-   [Ivan Nečas](https://github.com/iNecas)
-   [Petr Chalupa](http://blog.pitr.ch)
