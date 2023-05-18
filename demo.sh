#!/usr/bin/env bash
set -e -u -o pipefail

declare -r SCRIPT_PATH=$(readlink -f "$0")
declare -r SCRIPT_DIR=$(cd $(dirname "$SCRIPT_PATH") && pwd)

trap cleanup EXIT INT

declare -a PORT_FORWARDED_PIDS=()

apply() {
	local desc="$1"
	shift
	local f="$1"
	shift
	local show="${1:-yes}"

	echo applying: $desc : $f
	line 40

	if [[ "$show" != silent ]]; then
		bat $f
		sep
		wait_for_key
	fi
	kubectl apply -f $f --validate=false
}

build() {

	# make operator-image bundle bundle-image operator-push bundle-push IMAGE_BASE="local-registry:30000/observability-operator" VERSION=0.0.0-ci CONTAINER_RUNTIME=docker

	#  make operator-push bundle-push PUSH_OPTIONS=--tls-verify=false IMAGE_BASE="local-registry:30000/observability-operator" VERSION=0.0.0-ci

	kubectl wait --for=condition=Established crds --all --timeout=300s
	kubectl create -k deploy/crds/kubernetes
	./tmp/bin/operator-sdk run bundle \
		local-registry:30000/observability-operator-bundle:0.0.0-ci \
		--install-mode AllNamespaces \
		--namespace operators \
		--skip-tls \
		--index-image=quay.io/operator-framework/opm:v1.23.0

	kubectl rollout status deployment observability-operator -n operators

}

header() {
	local txt="$@"

	local len=40
	if [[ ${#txt} -gt $len ]]; then
		len=${#txt}
	fi

	echo -n "━━━━━"
	printf '━%.0s' $(seq $len)
	echo "━━━━━━━"
	echo -e "     $txt"

	echo -n "────"
	printf '─%.0s' $(seq $len)
	echo "────────"

	echo
}

line() {
	local len=${1:-30}

	echo -n "────"
	printf '─%.0s' $(seq $len)
	echo "────────"
}

sep() {
	local len=${1:-30}
	echo -n "    "
	printf '⎯%.0s' $(seq $len)
	echo
}

wait_for_key() {
	echo -en "\n  ﮸ Press a key to continue  ..."
	read -s
	echo
	echo
}

kill_after_key_press() {
	local pid=$1
	shift

	wait_for_key
	kill -INT $pid
}

port_forward() {
	local src=$1
	shift
	local target=$1
	shift
	local local_port=${1:-$target}

	kubectl get "$src"
	sep
	echo

	echo kubectl port-forward "$src" $local_port:$target --address 0.0.0.0 &
	kubectl port-forward "$src" $local_port:$target --address 0.0.0.0 &
	PORT_FORWARDED_PIDS+=($!)

	sleep 2
	line
	echo -e "\nopen: http://<your-ip>:$local_port"
}

list_all() {
	local what=$1
	shift
	echo "$what"
	line

	kubectl get "$what" $@
	sep
}

repeat() {
	local what=$1
	shift
	local ans=y

	while [[ "$ans" == "y" ]]; do

		$what "$@"
		sep
		read -p " repeat ? " ans
	done
}

prometheus_status() {
	local prom=$1
	shift

	echo "❯ run: kubectl get prometheus.monitoring.rhobs $prom -o jsonpath='{.status.conditions}' | jq -C ."

	kubectl get prometheus.monitoring.rhobs $prom \
		-o jsonpath='{.status.conditions}' | jq -C .
}

xstep_000_set_context() {
	header "✨ 0b0 ✨ -< RHOBS Prometheus Operator 🔱 >- ✨ 0b0 ✨ "
	echo "  ✶ Deploy RHOBS PO Operator fork 🔱"
	echo "  ✶ Deploy appliction"
	echo "  ✶ See metrics"
	sep
	wait_for_key
}

xstep_110_deploy_rhobs_po() {
	header "Deploy RHOBS Prometheus Operator"

	apply "catalog-source" subs/catalog-src.yaml
	apply "subscription" subs/subscription.yaml
}

step_120_watch_rhobs_po_installation() {
	header "Watch RHOBS Prometheus Operator Deployment"

	local pid
	watch -n 3 -c \
		"oc get -n openshift-operators deployments" &
	pid=$!

	sleep 5s
	kill -INT $pid || true

	oc get -n openshift-operators deployments
	wait_for_key
}

step_130_deploy_app() {
	header "Deploy Example App"

	apply "create ns" app/00-ns.yaml
	kubectl config set-context $(kubectl config current-context) --namespace=rhobs-po-demo

	apply "deployment" app/deploy.yaml
	apply "service" app/service.yaml
	apply "Service Monitor" app/service-mon.yaml

	kubectl wait --for=condition=Available deployment example-app

	wait_for_key
}

step_130_deploy_prometheus() {
	header "Deploy Prometheus"

	apply "service-account" ./prom/01-rbac/sa.yaml
	apply "clusterrole" ./prom/01-rbac/clusterrole.yaml
	apply "clusterrolebinding" ./prom/01-rbac/clusterrolebindings.yaml

	apply "prometheus" ./prom/02-deploy/prometheus.yaml

	wait_for_key
}

step_140_watch_po() {

	watch -n 3 -c \
		"kubectl get prometheus.monitoring.rhobs rhobs-prom" \
		" -o jsonpath='{.status.conditions}' | jq -C ." &
	pid=$!

	sleep 10s
	kill -INT $pid || true

	repeat prometheus_status rhobs-prom
	wait_for_key
}

step_150_port_forward_prom() {
	clear
	header "Application Metrics"

	port_forward sts/prometheus-rhobs-prom 9090

	line
	echo 'Prometheus UI: http://127.0.0.1:9090/targets'
	echo 'Run: count by (__name__, job, instance) ({__name__ =~ ".+"})'
	wait_for_key

}

disabled_130_show_running() {
	clear
	header "Show Stack Details"
	echo "  ✶ Prometheus"
	echo "  ✶ Alertmanager"
	sep
	echo
	wait_for_key

	list_all prometheus -l app.kubernetes.io/part-of=sample-monitoring-stack
	list_all alertmanager -l app.kubernetes.io/part-of=sample-monitoring-stack

	wait_for_key
	echo

	list_all statefulsets -l app.kubernetes.io/part-of=sample-monitoring-stack
	list_all services -l app.kubernetes.io/part-of=sample-monitoring-stack
	wait_for_key
}

disabled_140_show_prom_targets() {
	header "Prometheus up and running"
	port_forward sample-monitoring-stack-prometheus 9090

	line
	echo 'self monitoring: http://<ip>:9090/targets'
	echo 'Run: count by (__name__, job, instance) ({__name__ =~ ".+"})'
	wait_for_key
}

disabled_300_deploy_sample_app() {
	clear
	header "Deploy an Example App"

	apply "deployment " spy/deployment.yaml silent
	apply "service" spy/service.yaml

	kubectl wait --for=condition=Available deployment prom-spy
	port_forward prom-spy 8080

	echo "Application exposes /metrics"
	echo '{__name__=~ "promhttp.+"}' | clip

	wait_for_key
}

cleanup() {
	for pid in ${PORT_FORWARDED_PIDS[@]}; do
		kill -INT $pid 2>/dev/null >&2 || true
	done
}

step_999_thank_you() {

	header " ✨ The End ✨"
	echo
	echo "   Questions: "
	echo "      #forum-monitoring"
	echo "      #observability-operator-users on CoreOS slack"
	echo
	echo "                                        Sunil Thaha"
	line
}

main() {
	export KUBECONFIG=${KUBECONFIG:-~/.kube/cluster/obo}

	fns=($(declare -F | awk '{ print $3 }' | sort | grep '^step_' | grep -v _skip))

	for x in ${fns[@]}; do
		$x
		sleep 2
	done

	cleanup
	# echo "ran: ${fns[@]}"

	return $?
}

main "$@"
