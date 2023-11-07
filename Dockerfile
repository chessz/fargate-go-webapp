FROM ubuntu:latest

ARG GOVER=1.19.1

RUN apt update && apt install curl -y
RUN curl -L https://golang.org/dl/go${GOVER}.linux-amd64.tar.gz --output go${GOVER}.linux-amd64.tar.gz && \ 
    tar -xzf go${GOVER}.linux-amd64.tar.gz -C /usr/bin && \
    chmod a+x /usr/bin/go/bin && \
    rm go${GOVER}.linux-amd64.tar.gz 


WORKDIR /app

COPY main.go go.mod /app/
RUN CGO_ENABLED=0 /usr/bin/go/bin/go build -o webapp

ENTRYPOINT [ "./webapp" ]
