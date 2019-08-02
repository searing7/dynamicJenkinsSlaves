FROM ubuntu

ENV MAVEN_HOME /usr/share/maven
ENV JAVA_HOME /usr 
ENV NODEJS_HOME=/usr/lib/nodejs/node
ENV HOME /home/jenkins

#Override from Build arguments , below are defaulted if not 
ARG JENKINS_SLAVE_VERSION=3.29
ARG MAVEN_VERSION=3.6.1
ARG NODE_VERSION=10.9.0
ARG HELM_VERSION=v2.14.3
ARG TERRAFORM_VERSION=0.12.6
ARG PACKER_VERSION=1.4.2
ARG JAVA_VERSION=8=8.40.0.25 
ARG AGENT_WORKDIR=/home/jenkins/agent
# ARG JAVA_VERSION=9  # refer for versions https://github.com/zulu-openjdk

LABEL Description="Extending Jenkins agent executable (slave.jar) for building projects"

USER root

# Install necessary Packages
RUN apt-get --allow-unauthenticated update && apt-get --allow-unauthenticated upgrade -yq && \
    apt-get --allow-unauthenticated install --no-install-recommends  -yq build-essential openssl openssh-client apt-transport-https gnupg2\
    ca-certificates software-properties-common apt-utils locales libapr1 curl wget jq git vim bash\
    libtcnative-1 python3.6 python3-pip python3-setuptools \
    gettext unzip

# Add Docker repos
RUN curl -k -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -

RUN add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
    
RUN apt-get --allow-unauthenticated update && apt-get --allow-unauthenticated install -yq docker-ce

# Install zulu open-jdk 
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 0xB1998361219BD9C9  \
    && echo "deb http://repos.azulsystems.com/ubuntu stable main" >> /etc/apt/sources.list.d/zulu.list  \
    && apt-get -q --allow-unauthenticated update && apt-get -yq  --allow-unauthenticated install zulu-$JAVA_VERSION

# Install maven 
RUN curl -k -fsSL http://archive.apache.org/dist/maven/maven-3/$MAVEN_VERSION/binaries/apache-maven-$MAVEN_VERSION-bin.tar.gz | tar xzf - -C /usr/share \
    && mv /usr/share/apache-maven-$MAVEN_VERSION /usr/share/maven \
    && ln -s /usr/share/maven/bin/mvn /usr/bin/mvn
 
# Add  chrome for protractor tests
RUN wget --no-check-certificate -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | apt-key add -
RUN sh -c 'echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google.list'

# Install Node 
RUN mkdir /usr/lib/nodejs \
    && curl -k -fsSL "http://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.gz" | tar xz --directory "/usr/lib/nodejs" \
    && mv /usr/lib/nodejs/node-v$NODE_VERSION-linux-x64 /usr/lib/nodejs/node

# Set PATH
#ENV NPM_PACKAGES="${HOME}/.npm-packages"
ENV PATH="$NODEJS_HOME/bin:$PATH"

RUN npm install -g @angular/cli --unsafe

# Install Kubectl
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl \
   && chmod +x ./kubectl \
   && mv ./kubectl /usr/local/bin/kubectl

# Install Ansible 
RUN pip3 install ansible

RUN echo "==> Adding hosts for convenience..."  && \  
    mkdir -p /etc/ansible /ansible && \
    echo "[local]" >> /etc/ansible/hosts && \
    echo "localhost ansible_connection=local ansible_python_interpreter=/usr/bin/python3" >> /etc/ansible/hosts

# Override hosts in base images or replacing contents of /etc/ansible/hosts at runtime with volumes

ADD ansible.cfg /etc/ansible/ansible.cfg

# Install helm
RUN curl -kL https://storage.googleapis.com/kubernetes-helm/helm-${HELM_VERSION}-linux-amd64.tar.gz | tar xz \ 
   && mv linux-amd64/helm /usr/bin/helm  \
   && rm -rf linux-amd64 

# Install Terraform 
RUN wget --quiet -nc https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip  \  
   && unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d /usr/bin \ 
   && rm -rf terraform_${TERRAFORM_VERSION}_linux_amd64.zip 

# Install Packer 
RUN wget --quiet -nc  https://releases.hashicorp.com/packer/${PACKER_VERSION}/packer_${PACKER_VERSION}_linux_amd64.zip  \
   && unzip packer_${PACKER_VERSION}_linux_amd64.zip -d /usr/bin \
   && rm -rf packer_${PACKER_VERSION}_linux_amd64.zip 

# AWS tools installation 

RUN pip3 install awscli boto3
RUN mkdir ~/.aws && touch ~/.aws/credentials

# Copy TU settings.xml 
ADD maven_settings.xml $MAVEN_HOME/conf/settings.xml

# Globalconfig to TU Artifactory and Token
ADD npmrc /usr/lib/nodejs/node/etc/npmrc


# Install Slave jenkins jars 

RUN curl --create-dirs -fsSLo /usr/share/jenkins/slave.jar https://repo.jenkins-ci.org/public/org/jenkins-ci/main/remoting/${JENKINS_SLAVE_VERSION}/remoting-${JENKINS_SLAVE_VERSION}.jar \
  && chmod 755 /usr/share/jenkins \
  && chmod 644 /usr/share/jenkins/slave.jar

COPY jenkins-slave /usr/local/bin/jenkins-slave

ENV AGENT_WORKDIR=${AGENT_WORKDIR}
RUN mkdir /home/jenkins/.jenkins && mkdir -p ${AGENT_WORKDIR} && chmod 777 /usr/local/bin/jenkins-slave 
VOLUME /home/jenkins/.jenkins
VOLUME ${AGENT_WORKDIR}
WORKDIR /home/jenkins

# COPY TU Certs
RUN openssl s_client -showcerts -connect artifactory.transunion.com:443 2>/dev/null  | sed -ne '/-BEGIN CERTIFICATE-/,/-END CERTIFICATE-/p' >> tucerts
RUN keytool -import -noprompt -trustcacerts -file ./tucerts -alias tucerts -keystore /usr/lib/jvm/zulu-8-amd64/jre/lib/security/cacerts -storepass changeit
RUN echo $(cat ./tucerts) >> /etc/ssl/certs/ca-certificates.crt

# Clean up
RUN apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*  

ENTRYPOINT ["sh","/usr/local/bin/jenkins-slave"]
