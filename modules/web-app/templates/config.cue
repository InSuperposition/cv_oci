package templates

import (
	corev1 "k8s.io/api/core/v1"
	timoniv1 "timoni.sh/core/v1alpha1"
)

// #Config is the values schema for a stateless HTTP web app: one Deployment
// (single container, no volumes, no ServiceAccount token) fronted by one
// ClusterIP Service. It carries the PodSecurity `restricted` container context
// the cv_oci pipeline requires. `cv-frontend` is the first instance.
#Config: {
	// Injected by Timoni at build time (timoni.cue @tag).
	kubeVersion!:   string
	moduleVersion!: string

	// The version stamped as `app.kubernetes.io/version`. Timoni's own
	// `moduleVersion` (`-v`) is IGNORED for local-path builds (P13), so the
	// pipeline supplies this explicitly — for `cv-frontend` it is the checked-out
	// cv_frontend commit SHA. Defaults to `moduleVersion` for a bare `timoni build`.
	appVersion: *moduleVersion | string & =~"^[A-Za-z0-9][-A-Za-z0-9_.]{0,61}[A-Za-z0-9]$"

	// metadata.name / metadata.namespace come from the instance name/namespace.
	// #Metadata stamps app.kubernetes.io/{name,version,managed-by=timoni}.
	metadata:              timoniv1.#Metadata & {#Version: appVersion}
	metadata: labels:      timoniv1.#Labels
	metadata: annotations?: timoniv1.#Annotations

	// The pod/Service selector. Defaults to {app: <name>} to stay compatible
	// with the pre-5b `kubectl -l app=<name>` assertions; an instance may set
	// its own (e.g. an ephemeral smoke deploy adds a run-id label).
	selectorLabels: *{app: metadata.name} | {[string]: string}

	// The full container image reference (repo@sha256:...). Supplied per build
	// from the pipeline's `build` result — never pinned in the module.
	image!: string & =~"^[^:@[:space:]]+(:[^@[:space:]]+)?@sha256:[0-9a-f]{64}$"

	// The port the app listens on. Passed as the PORT env var and the
	// containerPort; the Service exposes it on 80.
	port: *44100 | int & >0 & <=65535

	// The HTTP path the readiness probe hits.
	readinessPath: *"/healthz" | string

	replicas: *1 | int & >0

	// Restricted container securityContext (matches the inline pipeline steps).
	securityContext: corev1.#SecurityContext & {
		runAsNonRoot:             *true | false
		runAsUser:                *1000 | int
		runAsGroup:               *1000 | int
		allowPrivilegeEscalation: *false | true
		capabilities: drop:       *["ALL"] | [...string]
		seccompProfile: type:     *"RuntimeDefault" | string
	}

	// Optional: extra labels merged onto every object's metadata (not the
	// selector). Optional: extra env vars for the container.
	extraLabels?: {[string]: string}
	extraEnv?: [...corev1.#EnvVar]
}

// #Instance renders the objects from a validated #Config.
#Instance: {
	config: #Config

	objects: {
		deploy: #Deployment & {#config: config}
		svc:    #Service & {#config: config}
	}
}
