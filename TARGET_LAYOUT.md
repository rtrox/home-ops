# Target Layout

## About

I'm currently in the process of migrating to a new repository structure. This Document is intended to outline that final structure while the migration is in progress to highlight which directories should and should not be referenced in new clusters.

## Structure

```
.
├── ansible                    # Ansible Playbooks for non-kubernetes infrastructure
├── .taskfiles                 # Taskfiles which leverage CLUSTER_CONFIG env for differentiation.
├── cluster-apps
│   ├── base
│   ├── bitty
│   ├── chongus
│   │   ├── default
│   │   ├── downloads
│   │   ├── kube-system
│   │   ├── system-upgrade
│   │   ├── system-controllers
│   │   ├── system
│   │   ├── network
│   │   ├── [...]
│   │   └── flux-system
│   └── components
│       ├── flux
│       ├── namespace
│       └── volsync
└── clusters
    ├── base
    │   ├── bootstrap
    │   │   └── templates
    │   ├── flux
    │   │   └── repositories
    │   │       ├── git
    │   │       ├── helm
    │   │       └── oci
    │   └── components
    │       ├── flux
    │       ├── namespace
    │       └── volsync
    ├── bitty
    │   ├── bootstrap
    │   │   └── templates
    │   ├── flux
    │   │   ├── cluster
    │   │   └── repositories   # Symlink/Kustomization to base/flux/repositories
    │   ├── components         # Symlink/Kustomization to base/components
    │   └── talos
    │       └── clusterconfig
    ├── chongus
    │   ├── bootstrap
    │   │   └── templates
    │   ├── flux
    │   │   ├── cluster
    │   │   └── repositories   # Symlink/Kustomization to base/flux/repositories
    │   ├── components         # Symlink/Kustomization to base/components
    │   └── talos
    │       └── clusterconfig
```
