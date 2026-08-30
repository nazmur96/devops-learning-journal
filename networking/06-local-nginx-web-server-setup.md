# 06 — Local Nginx Web Server Setup

**Objective:** Configure, optimize, and host static content locally.

**Tech:** Nginx (source list says Ubuntu/Debian — you're on **Fedora 44**).

## Key points

- **The server block (virtual host) model.** One Nginx instance serves many sites via
  `server {}` blocks matched by `server_name` and `listen`. Understand how a request is
  routed to the right block, and the default-server fallback.
- **Fedora vs Debian layout.** Debian/Ubuntu use `sites-available` + `sites-enabled`
  (symlinks). **Fedora doesn't** — configs go in `/etc/nginx/conf.d/*.conf` included
  from `nginx.conf`. Knowing this saves hours of confusion.
- **`location` matching precedence.** exact (`=`), prefix, regex (`~`/`~*`), and `^~`.
  This ordering trips up almost everyone — understand which wins.
- **Static file serving.** `root` vs `alias` (a classic footgun), `index`, `try_files`.
- **Custom error pages** via `error_page`, and **tuning**: `worker_processes auto`,
  `worker_connections`, `keepalive_timeout`, `sendfile`, `gzip`.
- **SELinux.** On Fedora, SELinux can block Nginx from reading files or binding ports
  even when file perms look right. This is a Fedora-specific reality.

## When to use it

- Hosting a static site/SPA, docs, or assets without a heavy app server.
- Fronting an app (reverse proxy — see project 05).
- Learning the server that underpins a huge fraction of the web.

## Scenario

You host two local sites, `blog.test` and `shop.test`, on one Nginx. A typo in a
`location` block makes CSS 404. Understanding `root` vs `alias` and `try_files` lets you
fix it in seconds instead of guessing.

## Where AI misleads

- **`sites-available`/`sites-enabled` on Fedora.** AI assumes the Debian layout and
  tells you to edit/symlink dirs that **don't exist on Fedora**. Top trap here.
- **`root` vs `alias` confusion.** AI mixes these up, producing wrong file paths. Know
  the difference cold.
- **Ignoring SELinux & firewalld.** AI debugs perms endlessly while SELinux
  (`setsebool`, `semanage`, `restorecon`) or firewalld (port not open) is the real cause.
- **`location` regex precedence.** AI's block ordering can silently match the wrong
  location. Verify with the precedence rules, not vibes.
- **Reload vs restart.** AI may `restart` (drops connections) when `nginx -s reload` /
  `systemctl reload` suffices; and forgets `nginx -t` to test config first.
