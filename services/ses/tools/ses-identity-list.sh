#!/bin/bash

HOST=localhost
SESSION=qwer

./call-ses-api.pl http://$HOST:8888/identity/list $SESSION

