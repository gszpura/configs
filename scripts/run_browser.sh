#!/bin/bash
if xdotool search --onlyvisible --class "firefox"; then
    xdotool search --onlyvisible --class "firefox" windowactivate
else
    firefox &
fi
