---
title: "Why Can't My App Connect to My Database?"
description: "A beginner's guide to the 4 checks on AWS: security group, PostgreSQL listening, pg_hba.conf, and the password. Read the error message and it tells you which one failed."
crosspost:
  devto: full
  linkedin: summary
  tags: [aws, postgres, beginners, devops]
  hashtags: [AWS, PostgreSQL]
  canonical_url: https://github.com/nazmur96/devops-learning-journal/blob/main/networking/why-cant-my-app-connect-to-my-database.md
  linkedin_image:
    path: img/db-connection-4-gates.png
    alt: "Can't connect to your database? 4 gates, in order; the error tells you which one is stuck. Gate 1, security group (the front gate): allow TCP 5432 from app-sg; if it fails, Connection timed out, which waits then gives up. Gate 2, PostgreSQL listening (someone is home): listen_addresses = '*'; if it fails, Connection refused, which fails instantly. Gate 3, pg_hba.conf (your name is on the visitor list); if it fails, no pg_hba.conf entry. Gate 4, username and password; if it fails, password authentication failed. The further down your error, the more already works."
  summary: |
    Your app can't reach its database. Before you start changing random settings: the connection has to pass 4 checks, one after another, and the error message tells you exactly which one failed.

    Think of visiting a friend in a secure building. The front gate lets you in (the AWS security group allows port 5432). Someone is home (PostgreSQL is listening on the network). Your name is on the visitor list (pg_hba.conf). And you know the password.

    Now read the error. "Connection timed out" waits, then gives up: gate 1, the security group. "Connection refused" fails instantly: gate 2, PostgreSQL isn't listening. "no pg_hba.conf entry" is gate 3. "password authentication failed" is gate 4.

    The good news hidden in errors: the further down that list, the more is already working. A password error means gates 1 to 3 are fine. And allow the database port from the app's security group, not from an IP, so replacing or adding servers never changes the rule.

    The full beginner's guide covers security groups, why 0.0.0.0/0 is risky, two test commands and a troubleshooting checklist. Link below.
---

*A beginner's guide to the 4 checks on AWS*

![Can't connect to your database? 4 gates in order: security group, PostgreSQL listening, pg_hba.conf, username and password, each with the error you see when it fails](https://raw.githubusercontent.com/nazmur96/devops-learning-journal/main/networking/img/db-connection-4-gates.png)

## The big idea first

When your app connects to a database, the connection has to pass **4 checks, one after another**. If any one fails, the connection fails.

Think of visiting a friend in a secure apartment building:

| Step | Building analogy | On AWS + PostgreSQL |
|---|---|---|
| 1 | The front gate lets you in | Security group allows the traffic |
| 2 | Someone is home to answer the door | PostgreSQL is listening for connections |
| 3 | Your name is on the visitor list | `pg_hba.conf` allows your app |
| 4 | You know the secret password | Username and password are correct |

Keep this picture in mind. Everything below explains one of these steps.

## Part 1: Security groups (gate 1)

### What is a security group?

A security group is a **firewall for your AWS resources**, like an EC2 instance (a virtual server). It decides which network traffic is allowed in.

Two rules to remember:

- **Everything coming in is blocked by default.** You add rules to allow what you need.
- **Replies are automatic.** If a request is allowed in, the response is allowed back out. You don't need a separate rule for that.

### What's in a rule?

Every inbound rule has 3 parts:

| Part | Question it answers | Example |
|---|---|---|
| Protocol | What kind of traffic? | TCP |
| Port | Which "door" on the server? | 22 |
| Source | Who is allowed to connect? | Your IP address |

### The "Type" dropdown is just a shortcut

When you pick a Type like SSH or HTTP, AWS fills in the protocol and port for you:

| Type | Port | Used for |
|---|---|---|
| SSH | 22 | Logging in to a Linux server |
| HTTP | 80 | Normal websites |
| HTTPS | 443 | Secure websites |
| Custom TCP | You choose | Anything else |

AWS does **not** check what's actually running on that port. Picking "SSH" just means "open port 22." If your SSH runs on port 2222, pick Custom TCP and type 2222.

## Part 2: Who can connect? (the source)

### What does `0.0.0.0/0` mean?

It means **anyone on the internet** (any IPv4 address).

### Does that mean anyone can log in?

No. It means anyone can **reach the door and try the lock**. They still need the right key, such as your SSH private key.

But it's still risky:

- **Bots** scan the internet all day and will try to break in.
- **Bugs** in software sometimes let attackers in without a key.
- **Future mistakes**, like a weak password, become much more dangerous.

### Safer options for SSH

- **Use "My IP" as the source.** AWS fills in your IP with `/32` at the end, which means "only this one address." If your home IP changes, you'll need to update the rule.
- **Use AWS Session Manager.** It gives you a terminal on your server without opening port 22 at all.

## Part 3: Ports

### What happens when you open a port?

| Situation | Result |
|---|---|
| Nothing is running on that port | Connection fails, nothing to talk to |
| An app is running on that port | Traffic can reach that app |

### Why big port ranges are dangerous

Opening `3000-9000` opens **6,001 ports**, not just the one you need.

Today, maybe only your web app is running. Next week you install PostgreSQL on port 5432, and it's suddenly exposed to the internet without you changing anything in AWS.

Common ports to know:

| Port | Usually used by |
|---|---|
| 3000 | Dev web apps, Grafana |
| 5432 | PostgreSQL |
| 6379 | Redis |
| 8080 | Jenkins, Tomcat |

> **Rule of thumb:** open only the ports you need, only to the sources that need them.

## Part 4: Connecting an app server to a database server

You have two servers:

- **App server:** runs your website
- **Database server:** runs PostgreSQL

You want the app to reach the database and block everyone else.

### Option A: allow the app server's IP (works, but annoying)

```text
Port: 5432    Source: 10.0.1.25/32
```

The problems:

- If you replace the app server, it gets a new IP, and you have to update the rule.
- If you add 10 app servers, you need 10 rules.

### Option B: allow a security group (better)

1. Create a security group called `app-sg`.
2. Attach it to your app server.
3. On the database's security group, allow:

```text
Port: 5432    Source: app-sg
```

This means: "Allow any server wearing the `app-sg` badge."

- **Replace a server?** Give the new one `app-sg`. No rule changes.
- **Add 10 servers?** Give them all `app-sg`. Still one rule.

> ⚠️ **One catch:** this only works when the app connects to the database's **private IP** (inside the same network). If it uses the database's public IP, the badge isn't recognized and the connection will time out.

## Part 5: The 4 gates in detail

### Gate 1: Security group

**Question:** Is traffic allowed to reach port 5432?

The database's security group needs a rule allowing TCP 5432 from `app-sg`.

### Gate 2: Is PostgreSQL listening?

**Question:** Is PostgreSQL accepting connections from other machines?

By default, PostgreSQL usually listens only to itself (`localhost`). Other servers can't reach it.

To fix it, edit `postgresql.conf`:

```ini
listen_addresses = '*'
```

This means "listen on all network connections." It does **not** mean anyone can log in. Gates 3 and 4 still protect you.

> 💡 You must **restart** PostgreSQL after changing this. A reload isn't enough.

### Gate 3: PostgreSQL's visitor list (`pg_hba.conf`)

**Question:** Is this app allowed to connect to this database as this user?

PostgreSQL has its own list of who's allowed, separate from AWS. You need a line in `pg_hba.conf` allowing your app server to connect to `mydb` as user `app`. For example, to allow the app server's whole subnet:

```text
# TYPE  DATABASE  USER  ADDRESS        METHOD
host    mydb      app   10.0.1.0/24    scram-sha-256
```

> 💡 After editing, **reload** PostgreSQL.

### Gate 4: Username and password

**Question:** Are the login details correct?

```text
Host:     10.0.2.40
Port:     5432
Database: mydb
Username: app
Password: (the correct one)
```

Even if gates 1–3 are perfect, a wrong password means no entry.

## Part 6: Reading error messages

The error message tells you which gate failed. **This is the most useful skill in this guide.**

| Error message | What it feels like | Which gate | What to check |
|---|---|---|---|
| `Connection timed out` | Waits a long time, then gives up | Gate 1 (network) | Security group rules, network settings, server firewall |
| `Connection refused` | Fails instantly | Gate 2 | Is PostgreSQL running? Is it listening on the network? |
| `no pg_hba.conf entry for host...` | PostgreSQL answered but said no | Gate 3 | Your `pg_hba.conf` rules |
| `password authentication failed` | Got all the way to login | Gate 4 | Username, password, does the user exist? |

> 💡 **Good news hidden in errors:** the further down the table your error is, the more is already working. A password error means gates 1–3 are fine.

> 💡 "Password authentication failed" also appears if the user doesn't exist at all. PostgreSQL does this on purpose so attackers can't guess usernames.

## Part 7: Two commands to test

Run these from the app server.

### Test 1: Can I reach the port? (gates 1–2)

```bash
nc -zv 10.0.2.40 5432
```

- **Success** means the network path works and something is listening.
- It does **not** test the password or `pg_hba.conf`.

### Test 2: Can I log in? (all 4 gates)

```bash
psql -h 10.0.2.40 -U app -d mydb
```

| Part | Meaning |
|---|---|
| `-h 10.0.2.40` | Database server's address |
| `-U app` | Log in as user `app` |
| `-d mydb` | Connect to database `mydb` |

- **Success** means all 4 gates pass.
- **Failure** means you read the error and match it to the table in Part 6.

## Part 8: Troubleshooting checklist

When the app can't connect, don't change random settings. Go in order:

1. **Security group:** Does the DB allow port 5432 from `app-sg`?
2. **Network:** Can the app server reach the DB's private IP? (`nc -zv`)
3. **PostgreSQL running:** Is it running and listening on the network?
4. **Visitor list:** Does `pg_hba.conf` allow this app, database, and user?
5. **Login:** Are the username and password correct? (`psql`)

## Quick recap

| Term | One-line meaning |
|---|---|
| Security group | AWS firewall that controls incoming traffic |
| Type dropdown | Shortcut that fills in the port |
| `0.0.0.0/0` | Anyone on the internet. Avoid for SSH and databases |
| `/32` | Exactly one IP address |
| Port range | Opens every port in the range. Keep it narrow |
| SG as source | "Allow anything with this badge" |
| `listen_addresses` | Makes PostgreSQL listen to the network |
| `pg_hba.conf` | PostgreSQL's own visitor list |

**The one thing to remember:**

> Security group → PostgreSQL listening → `pg_hba.conf` → Password

These are 4 separate locks. Fixing one doesn't fix the others. The error message tells you which lock is stuck.

## Good to know later (skip for now)

Once you're comfortable with the basics, look into these:

- **Network ACLs**, a second, stricter firewall layer on subnets.
- **Outbound rules** on the app's security group.
- **IPv6 (`::/0`)**, the IPv6 equivalent of `0.0.0.0/0`.
- **AWS RDS**, a managed database where gates 2 and 3 work a bit differently.
