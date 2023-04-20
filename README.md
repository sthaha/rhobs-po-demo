
# Running

```
./demo.sh
```



Ref: https://prometheus-operator.dev/docs/user-guides/getting-started/

* Install rhobs PO operator from custom OLM catalog
* Create the namespace  - rhobs-po-demo
* Install the example app
* Deploys Prometheus that monitors the example app
* Port forwards prometheus, so that you can play with the UI

## TIPS:

```sh
	oc port-forward sts/prometheus-rhobs-prom -n rhobs-po-demo 9090:9090 --address 0.0.0.0
```
