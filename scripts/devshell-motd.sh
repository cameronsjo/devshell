#!/bin/bash
# Login banner — shows available commands
# Sourced by /etc/profile.d/ on login

cat << 'BANNER'

  devshell

  s          tmux sessions (pick / create / kill / rename)
  p          project picker (~/Projects, git status indicators)
  g          git menu (status, diff, pull, push, commit, branch)
  c          common commands (docker, htop, disk — customize via ~/.commands)
  m          quick notes (saves to ~/notes/)

BANNER
