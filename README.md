# Kubernetes Ingress Nginx Certificate Issue Demo

## Prerequisites

1. Have [kind](https://kind.sigs.k8s.io/) installed on your machine.
2. Have kubectl and [helm](https://helm.sh/)
3. OpenSSL

## Setup the demo

Run `./install_repro.sh`.

This script should be idempotent so feel free to run it more than once if anything goes wrong.

## Seeing the bug in action

In the `hello-server.yaml` k8s template there are two ingress objects both being used for the `hello.test` domain with TLS established with 2 different certificates.

The `hello-misconfigured-ingress` references `hello-test-cert-wrong-san` which does not have validate SANs for the `hello.test` domain and thus can't be used.

The `hello-good-ingress` references `hello-test-cert` and it does have valid SANs and thus can be used.

### Validating the Bug

You should see

```bash
> curl --resolve hello.test:443:127.0.0.1 https://hello.test/hello
curl: (60) SSL certificate problem: unable to get local issuer certificate
More details here: https://curl.haxx.se/docs/sslcerts.html

curl failed to verify the legitimacy of the server and therefore could not
establish a secure connection to it. To learn more about this situation and
how to fix it, please visit the web page mentioned above.
```

if you run curl with verbose and `-k` for skipping TLS CA checks you'll see that the cert being presented is the fake kubernetes certificate

```bash
> curl -k -vvv --resolve hello.test:443:127.0.0.1 https://hello.test/hello
* Added hello.test:443:127.0.0.1 to DNS cache
* Hostname hello.test was found in DNS cache
*   Trying 127.0.0.1:443...
* TCP_NODELAY set
...
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
* ALPN, server accepted to use h2
* Server certificate:
*  subject: O=Acme Co; CN=Kubernetes Ingress Controller Fake Certificate
*  start date: Sep 12 01:19:58 2022 GMT
*  expire date: Sep 12 01:19:58 2023 GMT
*  issuer: O=Acme Co; CN=Kubernetes Ingress Controller Fake Certificate
*  SSL certificate verify result: unable to get local issuer certificate (20), continuing anyway.
...
```

### The Remedy

Run `kubectl edit -n demo hello-misconfigured-ingress` and change its `spec.ingressClassName` property to something else, e.g. `nginx-ignore` so that this ingress gets ignored by the running controller.

The following `curl` should suddenly begin working!

```bash
> curl --cacert certs/cacert.crt --resolve hello.test:443:127.0.0.1 https://hello.test/hello
Hello world!
```

### Conclusion

Should ingress controller be able to recognize that it can present a valid cert for this domain and gracefully resolve this misconfiguration?
