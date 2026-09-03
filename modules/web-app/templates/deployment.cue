package templates

import (
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
)

#Deployment: appsv1.#Deployment & {
	#config: #Config

	_labels: {
		if #config.extraLabels != _|_ {#config.extraLabels}
		#config.metadata.labels
	}
	_podLabels: {
		#config.selectorLabels
		if #config.extraLabels != _|_ {#config.extraLabels}
	}

	apiVersion: "apps/v1"
	kind:       "Deployment"
	metadata: {
		name:      #config.metadata.name
		namespace: #config.metadata.namespace
		labels:    _labels
		if #config.metadata.annotations != _|_ {
			annotations: #config.metadata.annotations
		}
	}
	spec: appsv1.#DeploymentSpec & {
		replicas: #config.replicas
		selector: matchLabels: #config.selectorLabels
		template: {
			metadata: labels: _podLabels
			spec: corev1.#PodSpec & {
				automountServiceAccountToken: false
				containers: [{
					name:            "app"
					image:           #config.image
					imagePullPolicy: "IfNotPresent"
					env: [
						{name: "PORT", value: "\(#config.port)"},
						if #config.extraEnv != _|_ for e in #config.extraEnv {e},
					]
					ports: [{containerPort: #config.port}]
					readinessProbe: httpGet: {
						path: #config.readinessPath
						port: #config.port
					}
					readinessProbe: periodSeconds:    3
					readinessProbe: failureThreshold: 20
					securityContext: #config.securityContext
				}]
			}
		}
	}
}
