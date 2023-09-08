FROM debian:buster-slim AS base

USER root
# Non-Interactive packages install/upgrade
RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections

WORKDIR /app
# copy the content of the local directory to the working directory
COPY . .
WORKDIR /app

#  Install pre-requisites
RUN apt-get update && apt-get upgrade -y && apt-get clean
RUN apt-get install -y python3 python3-dev python3-distutils gnupg wget unzip procps nano tar

# Install pip
RUN wget -q https://bootstrap.pypa.io/get-pip.py && \
    python3 get-pip.py --force-reinstall && \
    rm get-pip.py
RUN apt-get update -y

# Install Python pip packages dependencies (if any)
# RUN pip3 install -r requirements.txt

# Install Chrome
RUN wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add
RUN echo "deb [arch=amd64]  http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list
RUN apt-get -y update
RUN apt-get -qy install google-chrome-stable

# Install chromedriver
RUN wget -q https://chromedriver.storage.googleapis.com/2.41/chromedriver_linux64.zip
RUN unzip chromedriver_linux64.zip && rm chromedriver_linux64.zip
RUN mv chromedriver /usr/bin/chromedriver
RUN chown root:root /usr/bin/chromedriver
RUN chmod +x /usr/bin/chromedriver

# Install Nim
RUN wget -q https://nim-lang.org/download/nim-2.0.0-linux_x64.tar.xz
RUN ls -al
RUN xz -d nim-2.0.0-linux_x64.tar.xz
RUN tar -xf nim-2.0.0-linux_x64.tar

# Command to run on container start
# ENTRYPOINT[]"/app/nim-2.0.0-linux_x64/bin/nim"]
# CMD ["--version"]
ENTRYPOINT ["tail", "-f", "/dev/null"]