package templates

import corev1 "k8s.io/api/core/v1"

#Service: corev1.#Service & {
	#config: #Config

	_labels: {
		if #config.extraLabels != _|_ {#config.extraLabels}
		#config.metadata.labels
	}

	apiVersion: "v1"
	kind:       "Service"
	metadata: {
		name:      #config.metadata.name
		namespace: #config.metadata.namespace
		labels:    _labels
	}
	spec: corev1.#ServiceSpec & {
		type:     "ClusterIP"
		selector: #config.selectorLabels
		ports: [{
			name:       "http"
			port:       80
			targetPort: #config.port
			protocol:   "TCP"
		}]
	}
}
