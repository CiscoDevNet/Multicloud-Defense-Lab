#!/bin/bash
sudo apt-get update
sudo apt-get install -y w3m
sudo apt-get install -y apache2
sudo systemctl start apache2
sudo systemctl enable apache2
cd ../../var/www/html/
cp /home/ubuntu/gcp-app.png /var/www/html/gcp-app.png
cp /home/ubuntu/index.html /var/www/html/index.html
cp /home/ubuntu/status /var/www/html/status