#!/bin/bash
sed -i s/botToken/"$bottoken"/ flaskAlert.py
sed -i s/xchatIDx/"$chatid"/ flaskAlert.py

/usr/bin/gunicorn -w 4 -b 0.0.0.0:9119 flaskAlert:app
