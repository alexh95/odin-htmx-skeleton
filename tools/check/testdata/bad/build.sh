#!/usr/bin/env sh
case "$p" in
  bad)   store=sqlite id=platform/authz/anonymous client=vanilla theme=full ;;
  ghost) store=memory id=platform/authz/anonymous client=vanilla theme=lite ;;
esac
