
# Running

Ref: https://prometheus-operator.dev/docs/user-guides/getting-started/

* Create the namespace opo-demo
* Create the example app
* Deploy Prometheus
* Let it run and then 

```sh
	oc port-forward sts/prometheus-prometheus -n opo-demo 9090:9090 --address 0.0.0.0
```
