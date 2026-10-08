---
title: "How Code Goes from Your Laptop to the User"
description: "Every language solves the same four problems: entry point, dependencies, build, and final output. Go, Rust, Java, C#, Python and JavaScript side by side, and why the final output decides your Docker image."
crosspost:
  devto: full
  linkedin: summary
  tags: [devops, docker, programming, beginners]
  hashtags: [DevOps, Docker]
  canonical_url: https://github.com/nazmur96/devops-learning-journal/blob/main/foundations/how-code-goes-from-laptop-to-user.md
  linkedin_image:
    path: img/build-chain-by-language.png
    alt: "Table: every language, same 4 jobs. Single binary, nothing to install: Go (main.go, Go Modules, go build, single binary) and Rust (src/main.rs, Cargo, cargo build, binary or .wasm). Needs a runtime: Java (Main.java, Maven or Gradle for both, .jar or .war, JVM), C# (Program.cs, NuGet, dotnet build, .dll or executable, usually .NET), Python (main.py, pip, Poetry or uv, usually no build, source, .whl or .exe, Python), JavaScript (index.html to index.js, npm, yarn or pnpm, Vite or Webpack, dist folder, browser). The final output decides your container image: binary to distroless, .jar to JRE, dist to Nginx."
  summary: |
    Every programming language solves the same four problems. Where does the program start? How do I get other people's code? How do I turn my code into something I can ship? And what do I actually hand to the user or server? Entry point, dependency manager, build tool, final output.

    The tools change names; the jobs don't. Go has main.go, Go Modules and go build. In Java, Maven or Gradle does both the shopping and the cooking. JavaScript splits them: npm fetches, Vite builds. Python usually has no build step at all.

    Most of the differences come from one question: does the output need a runtime installed? Go and Rust compile to a single binary that runs by itself. Java needs the JVM, C# the .NET runtime, Python the interpreter, and JavaScript a browser or Node.

    That's exactly what you need to know when writing Dockerfiles. A Go or Rust binary goes into a tiny distroless image. A .jar goes into a JRE image. A frontend's dist folder gets served by Nginx, with no Node in the final image. It's why multi-stage builds are everywhere: stage 1 has the build tools, stage 2 only the output.

    The full write-up goes language by language, with a recipe analogy and two things people often get wrong. Link below.
---

![Every language, same 4 jobs: entry point, dependencies, build tool and final output for Go, Rust, Java, C#, Python and JavaScript](https://raw.githubusercontent.com/nazmur96/devops-learning-journal/main/foundations/img/build-chain-by-language.png)

## The big idea

Every programming language solves the same four problems:

1. **Where does the program start?** → the *Entry Point*
2. **How do I get other people's code (libraries)?** → the *Dependency Manager*
3. **How do I turn my code into something ready to ship?** → the *Build Tool*
4. **What do I actually give to the user or server?** → the *Final Output*

A simple analogy is a recipe:

| Step | Recipe analogy | Software |
|---|---|---|
| Entry Point | "Step 1" of the recipe | The first file that runs |
| Dependency Manager | Going shopping for ingredients | Downloading libraries |
| Build Tool | Cooking | Compiling and packaging |
| Final Output | The finished dish | The file you deploy |

The tools have different names in each language, but the job is the same.

## Two families of languages

Most of the differences come from one question: **does the final output need a runtime installed to work?**

**Family A: compiled to a single binary (Go, Rust).**
The output is one file that runs by itself. You copy it to a server and run it. Nothing else needs to be installed.

**Family B: needs a runtime (Java, C#, Python, JavaScript).**
The output only works if a "helper program" is installed on the machine:

- Java needs the **JVM** (Java Virtual Machine)
- C# needs the **.NET runtime**
- Python needs the **Python interpreter**
- JavaScript needs a **browser** (or Node.js on a server)

With this in mind, the rest is easier to remember.

## Language by language

### 1. JavaScript (frontend)

- **Entry Point:** `index.html` loads `index.js` (or `main.js`)
- **Dependencies:** npm, yarn, or pnpm, listed in `package.json`
- **Build Tool:** Vite or Webpack. These combine many files into a few, make them smaller, and make them work in all browsers.
- **Output:** A folder (usually `dist/`) with `.js`, `.css`, and image files. A web server or CDN serves these to the browser.

### 2. Java

- **Entry Point:** A class with a `public static void main()` method, such as `Main.java`, or `Application.java` in Spring Boot
- **Dependencies:** Maven (`pom.xml`) or Gradle (`build.gradle`)
- **Build Tool:** The same Maven or Gradle. They both download libraries and build.
- **Output:**
  - `.jar`: runs directly with `java -jar app.jar` (the modern way)
  - `.war`: deployed into a server like Tomcat (the older way)

### 3. Python

Python is interpreted. It reads and runs your `.py` files directly, so normally there is no real "build" step.

- **Entry Point:** `main.py` (or whichever script you run first)
- **Dependencies:** pip with `requirements.txt`, or newer tools like Poetry or uv with `pyproject.toml`
- **Build/Packaging Tool:** Only needed in special cases:
  - setuptools or Poetry, to publish a library for others
  - PyInstaller, to make a standalone program for people without Python
- **Output:** Usually just your source code plus its dependencies. Optionally a package on PyPI (a `.whl` file) or a `.exe` from PyInstaller.

### 4. Go

Go was built by Google to compile fast and to produce one self-contained file. Everything you need comes with Go itself.

- **Entry Point:** `main.go`, specifically the `main()` function inside `package main`
- **Dependencies:** Go Modules (`go.mod` and `go.sum`)
- **Build Tool:** `go build`, which is built in
- **Output:** One binary file that includes your code and all libraries. No runtime needed.

### 5. Rust

Rust focuses on speed and safety. One tool, Cargo, handles almost everything.

- **Entry Point:** `src/main.rs`
- **Dependencies:** Cargo. Libraries are called "crates" and are listed in `Cargo.toml`.
- **Build Tool:** `cargo build`, which calls the `rustc` compiler for you
- **Output:** One fast binary file, or a `.wasm` (WebAssembly) file that runs in browsers

### 6. C# / .NET

Modern C# works much like Java: code is compiled for a runtime, not directly for the machine.

- **Entry Point:** `Program.cs`
- **Dependencies:** NuGet, listed in the `.csproj` file
- **Build Tool:** `dotnet build` (which uses MSBuild behind the scenes)
- **Output:** A `.dll` file that runs on the .NET runtime, or a self-contained executable that bundles the runtime inside

## Summary table

| Language | Entry Point | Dependency Manager | Build Tool | Final Output | Needs runtime? |
|---|---|---|---|---|---|
| JavaScript | `index.html` / `index.js` | npm / yarn | Vite / Webpack | `dist/` folder (JS, CSS, assets) | Yes (browser) |
| Java | `Main.java` | Maven / Gradle | Maven / Gradle | `.jar` / `.war` | Yes (JVM) |
| Python | `main.py` | pip / Poetry / uv | Usually none (PyInstaller optional) | Source code, `.whl`, or `.exe` | Yes (Python) |
| Go | `main.go` | Go Modules | `go build` | Single binary | No |
| Rust | `main.rs` | Cargo | `cargo build` | Single binary / `.wasm` | No |
| C# | `Program.cs` | NuGet | `dotnet build` | `.dll` / executable | Usually (.NET) |

## Two things people often get wrong

- **Python `.pyc` files are not a deployment output.** Python creates them automatically as a speed cache. You don't ship them.
- **In Java and Rust, one tool does two jobs.** Maven/Gradle and Cargo both download dependencies *and* build. Go is similar with the `go` command. Only JavaScript clearly separates the two (npm + Vite).

## Why this matters for DevOps

This is the knowledge you need when writing Dockerfiles and CI pipelines. The **Final Output** decides what goes into your container image:

- **Go / Rust:** Copy just the binary into a tiny image (`scratch` or distroless). The result is very small and secure.
- **Java:** Build the `.jar`, then copy it into an image that has a Java runtime (JRE).
- **Python:** Use a Python base image, install dependencies, and copy in the source code.
- **JavaScript frontend:** Build the `dist/` folder, then serve it with Nginx. Node isn't needed in the final image.

This is why **multi-stage Docker builds** are common: stage 1 has all the build tools, and stage 2 contains only the final output.
