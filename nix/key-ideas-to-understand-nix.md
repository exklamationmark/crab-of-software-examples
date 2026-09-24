# Key ideas to understand Nix

*Jul 17, 2026*

Accompany materials:
https://github.com/exklamationmark/crab-of-software-examples/tree/main/nix

This note started as an attempt to teach my 2025-self, who was trying to vibe-code my way to use `Nix`, `home-manager`.
While doing so, I was also trying to understand what Nix does differently from a container (docker) image,
Bazel, `make`, various package managers (`go mod`, `cargo`), Jenkins/GitHub actions, etc and so many other related things.

> To be fair, the promise of vibe-coding held: Without diving in too deep, I did get something that managed my `/home/[user]`, packages on the machine and even Ubuntu’s system settings (via `dconf`).

However, things got trickier as I tried more complex things:

- Manage a fleet of machines: work MacPro, work Lenovo laptop, personal laptop, the 3x Linux boxes in my homelab, the DNS Raspberry Pi, my SurfacePro-converted-to-linux-tablet, etc (a bit much, but I assure you they are all well-utilized and have a purpose).

- Set up Nix-based development/CI environment for projects we manage at work.

- Teach Nix to my colleagues

- Argue in proposals on why we should replace X with Nix.

As it turned out, using an LLM doesn’t teach you the nuances.
However, dissecting its output does ^\_^

I will try to cover the concepts that led to my own "aha" moment. It won’t be a beginner guide, as I benefited from lots of exposure with build systems across OS/CPU architectures, deploying software in multiple environments, plus a long struggle with Haskell. The past pains from those did smooth out some of the humps for me. However, it also means I might gloss over things
that others find non-trivial.

Still, I’m hopeful that this will give you the keystones to build your own understanding about Nix.

> P.S. Search for `keystone` below if you want the tl;dr

------------------------------------------------------------------------

## Working back from what we use Nix for

You probably want to learn Nix for what it does, rather than for how it works. Usually, that will be one of these:

- You want to manage the configuration of a fleet of machines, (e.g. your devices, your company’s devices, servers, etc). Here, configuration usually means what binaries and files are installed on them.

- You want to set up a consistent development environment for a project.

- You want to get a program to build hermetically.

Let’s pick machine configuration since that’s easy to relate. This process involves installing packages and writing to certain files. If you do this manually, you could run `apt install` or `brew install`, then write the other files yourself. If you are like me, you would also need a script/repeatable process, because for the last 10+ years, I have never been able to correctly follow the install steps for my own laptops! :D

Our example is to set up a machine where a single binary (`just`) [is always installed](https://github.com/exklamationmark/crab-of-software-examples/blob/main/nix/simple-home-manager/flake.nix#L27-L29). We would write something like this:

```
# flake.nix
{
  # ...
  outputs = { self, nixpkgs, home-manager, ... }:
    {
      homeConfigurations."USERNAME" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          {
            # ...

            # installed packages
            home.packages = with pkgs; [
              just
            ];
          }
        ];
      };
    };
}
```

And then run a command to actually install it.

```
$ sudo nix run home-manager/master -- switch -b backup --flake .#USERNAME
```

Walking backwards from the goal, we can use this model:

```

 ┌────────────────────────────────────────────────────────────────────────────┐
 │ Configuration targets: /home/[user]/*, binary packages, env variables, etc │
 └────────────────────────────────────────────────────────────────────────────┘
                     │
           is side-effect of running
                     │
                     ▼
         ┌─────────────────────────┐                           ┌─────────┐
         │     Nix home-manager    │──────── pull from ───────►| nixpkgs |──┐
         └─────────────────────────┘                           └─────────┘  │
                     │                                              ▲       │
          use data evaluated from                                   │       │
                     │                                              │       │
                     ▼                                              │       │
     ┌────────────────────────────────┐                             │       │
     │ Nix configuration files (.nix) │──────── reference ──────────┘       │
     └────────────────────────────────┘                                     │
                     │                                                      │
               is written in                                                │
                     │                                                      │
                     ▼                                                      │
          ┌─────────────────────────┐                                       │
          │ Nix functional language │◄─────── is written in ────────────────┘
          └─────────────────────────┘

```

### Q1: What does home-manager do?

It turns out that `home-manager` consumes a structured data (think `JSON`, but more powerful) that is like this:

```
{
  outputs: {
    homeConfigurations: {
      USERNAME = {
        "activationPackage": <<A function that install binaries/files>>;
      };
    };
  };
}
```

Then it simply executes the function at `outputs.homeConfigurations."USERNAME".activationpackage`, which actually installs things on your machine.

### Q2: How is `activationPackage` created?

Like `home-manager`, we would need to evaluate the expression in `flake.nix` to get the expected structure. Luckily, we can interactively do this with `nix repl`

```
# Eval the flake (. means at the root)
$ nix repl

# Load flake
nix-repl> :lf .
Added 12 variables.
_type, dirtyRev, dirtyShortRev, homeConfigurations, inputs, lastModified, lastModifiedDate, narHash, outPath, outputs, sourceInfo, submodules

# Print the keys of the flake's "outputs"
nix-repl> builtins.attrNames outputs

# Explore more levels below
[ "homeConfigurations" ]
nix-repl> builtins.attrNames outputs.homeConfigurations
[ "mtong" ]
nix-repl> builtins.attrNames outputs.homeConfigurations."mtong"
[
  "_module"
  "_type"
  "activation-script"
  "activationPackage"
  "class"
  "config"
  "extendModules"
  "graph"
  "newsDisplay"
  "newsEntries"
  "options"
  "pkgs"
  "type"
]
```

Seeing this process is really important to quickly grok Nix. Almost all the complex work we will ever do is in service of creating this structured blob, which has `outputs.homeConfigurations."USERNAME".activationpackage`.

**How does this happen exactly?**

Recall that the `flake.nix` has a `outputs.homeConfigurations."USERNAME"`. A key process must be happening here. And that’s the `home-manager.lib.homeManagerConfiguration {...}` [function call](https://github.com/exklamationmark/crab-of-software-examples/blob/main/nix/simple-home-manager/flake.nix#L18-L34):

```
    let
      # ...
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      homeConfigurations."USERNAME" = home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          {
            home.username = "USERNAME";
            home.homeDirectory = "/Users/USERNAME";
            home.stateVersion = "26.05";

            home.packages = with pkgs; [
              just
            ];

            programs.home-manager.enable = true;
          }
        ];
      };
```

The functional call can be understood in a re-written form:

```
# let
#   pkgs = nixpkgs.legacyPackages.${system};
# in

home-manager.lib.homeManagerConfiguration {
  pkgs = pkgs; # This is `inherit pkgs`. The RHS `pkgs` is from the `let` block
  modules = [
    {
      home = {
        username = "USERNAME";
        homeDirectory = "/Users/USERNAME";
        stateVersion = "26.05";

        packages = [
          pkgs.just
        ];
      };

      programs = {
        home-manager = {
          enable = true;
        };
      };
    }
  ];
};
```

This can be read easier now:

- The user is `USERNAME`.

- The home dir is `/Users/USERNAME` (this was on a Mac).

- Install a single package called `just`.

- Enable a program called `home-manager`.

It’s not black magic anymore, right.

## Keystone: eval into structured data

For me, finding this process was 60-70% of the learning. The other use cases involving Nix, like creating development environments or building a binary hermetically are really just about:

- Knowing what structured data (Nix attribute set) is expected

- Writing code/functions that read other inputs and create these attribute sets.

------------------------------------------------------------------------

# Build it up: project dev env

With the key concept out of the way, it became pretty easy to do more for me.

When I pitch using Nix at work, one of the use cases was to create a consistent development environment for everyone.

> YMMV! This use case fits us, but might not fit yours.

We mostly build services/CLI in Go, though for developing, we need other
tools like `helm`, `kustomize`, `kind`, `argocd`, `kwow`, `helm-docs`, `yq`, etc.
Plus we also set different kernel params (only on Linux and not Mac) and
a variety of other small things, just to get started.

Our developers use a mix of Linux PCs (Intel or AMD CPUs)
and Mac (Intel or ARM CPUs).

We went through a history with this:
- We had the most primitive form of "developer environment": a README checklist
  a long, long time ago.
- The more recent attempt was a `Makefile` with special targets for pulling
  binaries based on `(OS, ARCH)`. But even that got so complex that we
  started using a `download.sh` script in the `download/$*` target.
- And before you ask, yes, we also had a "development container" + bind-mounted
  source setup, which wrapped around the Makefile.

That is to say, I picked Nix not because it is shiny, but because I feel it
genuinely reduced my maintenance cost for the dev environment work, which we
made a few attempts to improve.

> Even a (supposedly) simple task like pulling a binary matching `(OS, ARCH)` is
> not straightforward. Because many projects liberally pick between
> `aarch64`/`arm64`, `x86_64`/`amd64`, `Linux`/`linux`, `darwin`/`mac` in download URLs :)

At this point I have used Nix personally for two years and professionally for one.
I’m starting to prefer a Nix dev environment over running a development container with all the tools + bind-mounting the source code.
We also tried building cross-platform Docker images, but it turned out to be so much more work.

And we can't silently suffer [a significant performance degradation when running
x86 instructions on ARM](https://support.apple.com/en-us/102527).
Plus, the [UID/GID gotchas when bind-mounting](https://eastondev.com/blog/en/posts/dev/20251217-docker-mount-permissions-guide/)
pop up so many times, too.

Turns out you can write something like this in a repo:

```
# flake.nix
{
  description = "k8s GitOps project";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.jq
            pkgs.kubectl
            pkgs.helm
            pkgs.kustomize
          ];
        };
      });
    };
}
```

And anyone on any combination of Linux/Mac and Intel/AMD/ARM will get their tools after running `nix develop`. You can even pin versions, set env variables and various setup scripts in the Nix dev shell.

And on CI machines, I just need to install Nix + run `nix develop` and just call my test script as usual. CI runs are still fairly isolated with Nix wrapping them.

The best part is when you exit the dev shell, all these setups vanish without interfering with your actual machine’s config.

------------------------------------------------------------------------

## Confusing things: Nix packages, Nix OS, Nix language

There is this infamous picture about Nix being 3 different things.

![Different parts of Nix (REF: https://xeiaso.net/talks/2024/nix-docker-build/)](https://substackcdn.com/image/fetch/$s_!QGJd!,w_1456,c_limit,f_auto,q_auto:good,fl_progressive:steep/https%3A%2F%2Fsubstack-post-media.s3.amazonaws.com%2Fpublic%2Fimages%2F49e4a0e4-0b24-4f9c-ad0d-b2ade2c37bd6_823x718.png)

Different parts of Nix (REF: https://xeiaso.net/talks/2024/nix-docker-build/)

I was definitely confused about these at first. But over time, trying to take note of where the word Nix is used helps clarify things.

For most beginners, I think we would just muck around with Nix the language (what we write in `*.nix` files) and Nix packages (those `pkgs.[packageName]` that we install).

## Nix must stay (functional) "pure"

I might be technically wrong here, but I have found that trying to use "dynamic" information like substituting `$PWD` to be tricky. As with many languages I have worked with, the complexity is not in the language syntax, but in the runtime/evaluation.

My usage is fairly simple: When configuring Neovim, symlink the `~/.config/nvim/spell` to my configuration repo’s `modules/home-manager/nvim/spell`. That way, updating the dictionary in Vim will automatically be recorded in the configuration repo, which will help with propagating it across other machines. Here, a symlink is superior to pure Nix config, as my dictionary of variable names changes a lot more frequently than machine reconfiguration.

What I discovered when running `home-manager switch` from the configuration repo was this: `$PWD` points to my `$HOME`, instead of the configuration repo. And any use of `${./relative/path}` was pointing to the Nix store instead of my repo.

Eventually, I just took the easy way of declaring the repo path as a top-level param, and propagating it down to all parts of the Nix config.

Something like this:

```
  outputs =
    { self, nixpkgs, home-manager, darwin, nix-homebrew, ... }@inputs:
    let
      # VARIABLES
      # ------------------------------------------------------------------------

      # We might need to symlink config files to this repo, for easier edits.
      # However, Nix can only expand $HOME correctly.
      # Usage of ${./relative/path}, $PWD/relative/path won't work as expected.
      # => Use a global variable to make it easier to reference the repo path.
      repoCheckoutDir = "workspace/src/github.com/ME/dotfiles";

      # ...

      mkHome =
        { stateVersion, system, host, username }:
        let
          repoRoot = "/home/${username}/${repoCheckoutDir}";
        in
        home-manager.lib.homeManagerConfiguration {
          # ...
          extraSpecialArgs = { inherit inputs stateVersion username host repoRoot; };
        };
```

It does help that Nix passes info around using an attribute set with named keys, so the signature of modules that don’t use the `repoRoot` don’t get bloated.

Whether this is good Nix is questionable, but maybe it is a case of necessary complexity, since the path to the configuration repo is truly part of the configuration inputs. At least from my experience with other forms of abstractions in Go/Rust/Helm charts/other config modules, it feels right for now.

## vs Bazel

I will probably cover Nix vs Bazel at some point (we are not large enough for production Bazel though). But my take from researching them is this:

- The smallest unit you can “build” in Nix is a package (e.g: `pkgs.jq`), which can be quite large when you develop things at scale.

- Bazel breaks the build process into even smaller pieces (source code → obj files, linking, etc). And if your org's software is really large (like Google/Facebook/Microsoft large), some other engineers in the company might be building the same obj files recently. Thus, you can cache and amortize the cost of those small steps. Though this benefit rarely shows up for any small/medium orgs.

- Bazel supports much more complex remote builds, caching, etc. Again, these only matter when you are really large.

- Getting started with Bazel used to be a lot more work (like downloading the Java app and running it). But it supports running on Windows if that matters.

------------------------------------------------------------------------

# Closing thoughts

As a personal and professional choice, I’m a lot more confident in recommending to small/medium orgs now. It’s no longer just a cool/fancy tech, but actually solves real problems and saves my time in quantifiable ways.

And with LLMs, it’s getting a lot more comfortable to parse the pure functional code that Nix uses now, so the barrier to entry is really low.
