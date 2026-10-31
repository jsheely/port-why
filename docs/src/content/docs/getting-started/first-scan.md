---
title: Your first scan
description: Find a listening port, inspect its owner, and open the project behind it.
---

Launch Port Why. The app scans your machine on a background isolate and refreshes the list every two seconds.

## Read the deck

Each card represents a port. The large number is the port; the smaller addresses show where it is bound. The card also shows the process or framework, project, working folder, and process ID when available.

| Color | Scope |
| --- | --- |
| Cyan | Projects |
| Violet | Apps |
| Yellow | System |

On Windows, cards also show how long a port has been open. macOS and Linux do not expose that information.

## Find your server

Press **Ctrl+F** (**Cmd+F** on macOS) and type a port such as `3000`, a project name, or part of a command line. Every word in the filter must match. Press **Esc** to clear it.

Click a card to expand its full command line, executable, working folder, parent process, and bind addresses. Detection is inferred: these details let you check why a framework or project was named.

## Act on the owner

- Use the folder action to open its working folder in your file manager.
- Use the star to add a port to your favorites. Favorites appear in the top bar.
- Use the stop action when you want to end the owning process. Review the confirmation first: a process may own several ports. For Docker cards, the action stops the container.

Ports `3000`, `5173`, and `8080` are favorites by default. Click a favorite to jump to its current owner.

## Refresh on demand

Press **F5** (**Cmd+R** on macOS) to rescan from scratch. Ordinary updates happen automatically; there is no need to repeatedly refresh.
