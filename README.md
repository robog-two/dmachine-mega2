# `declare.sh`
Use a declarative style to manage your infrastructure as code, all with bash scripts and bare-metal Debian.

*Probably don't use this in production. If you do, let me know if you run into any problems or see any flaws. My issues are open, as always.*

*Claude Code was used to assist in the creation of this project. See [my stance on using Generative AI in my work](https://robog.net/docs/generative-ai-usage/).*

## Install

1. Fork this repository to its own "machine" repository. This will be where you store the declarative configuration for the machine.
2. Configure that repository to send a GitHub webhook to http://your.server.net:23614/webhook (recommended but not required, the server will check every 24h for new commits)
3. Set up a Debian machine to your ideal "blank" configuration. You should use the same setup on all machines, ideally. You will need btrfs on `/`, and you should make a separate persistent partition, you might want it later.
3. Run the below command (script will prompt for repository)

```bash
sudo su
curl -fsSL https://sh.robog.net/declare | bash
```

## Why

I've been working on my homelab setup lately after some poorly executed upgrades broke SSH on my machines. Having worked with AWS and "infrastructure as code," I wondered if there was a way to do this on my own machines. I found Ansible a little too finicky and NixOS is a little too bespoke, so I wondered if there was a way to make a declarative system that used good old bash running on old reliable Debian. I used Claude Code to throw together a quick prototype of my vision, leveraging `btrfs` to do a system restore and `systemd` to run some special init scripts.

On one hand, it feels hacky. On the other hand, it feels classic and straightforward. Why write a new OS, or a bunch of Python or YAML? Debian, like most *nixes, are often managed through the command line. This method basically transforms this workflow into the declarative and modern workflow we've come to expect, using the tools and tricks we've become familiar with.

## How

- Webhook listens for events
- A script checks if there is new commits (to double-check the very spoofable HTTP webhook), if so it restores to a clean state, then restarts the server.
- A systemd service runs the bootstrap script on every system startup
- A boostrap script updates the other scripts and itself, then runs itself again, starting the webhook and running your shell scripts—or any other code they might call in a language of your choice—on a "blank slate," each time you update the configuration, it creates the server's state in its entirety
