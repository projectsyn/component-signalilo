local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.signalilo;
local namespace = params.namespace;

local secret = kube.Secret('signalilo') {
  metadata+: {
    namespace: params.namespace,
  },
  // Required for kube.SecretKeyRef()
  data: {
    icinga_password: '',
    alertmanager_token: '',
  },
  // Secrets are assumed to be Vault refs
  stringData: {
    icinga_password: params.icinga.password,
    alertmanager_token: params.alertmanager_token,
  },
};

// Generate SIGNALILO_ICINGA_STATIC_SERVIC_VAR environment variable. Signalilo
// expects key=value pairs separated by newlines for each variable which
// should be set to a static value on each Icinga service.
local env_static_icinga_service_vars =
  local vars = params.icinga.static_service_vars;
  if vars != null && std.length(vars) > 0 then
    std.prune({
      SIGNALILO_ICINGA_STATIC_SERVICE_VAR: std.join(
        '\n',
        [ '%s=%s' % [ k, vars[k] ] for k in std.objectFields(vars) ]
      ),
    })
  else
    {};

local deployment = kube.Deployment('signalilo') {
  metadata+: {
    namespace: params.namespace,
    labels+: {
      'app.kubernetes.io/name': 'signalilo',
      'app.kubernetes.io/instance': inv.parameters.cluster.name,
      'app.kubernetes.io/managed-by': 'syn',
    },
  },
  spec+: {
    template+: {
      spec+: {
        containers_+: {
          signalilo: kube.Container('signalilo') {
            image: params.images.signalilo.image + ':' + params.images.signalilo.tag,
            env_+: std.prune({
              SIGNALILO_UUID: inv.parameters.cluster.name,
              SIGNALILO_ICINGA_HOSTNAME: if params.icinga.hostname == null
              then
                error 'parameters.signalilo.icinga.hostname is required'
              else
                params.icinga.hostname,
              SIGNALILO_ICINGA_URL: if params.icinga.url == null then
                error 'parameters.signalilo.icinga.url is required'
              else
                params.icinga.url,
              SIGNALILO_ICINGA_CA: params.icinga.ca,
              SIGNALILO_ICINGA_USERNAME: if params.icinga.user == null then
                error 'parameters.signalilo.icinga.user is required'
              else
                params.icinga.user,
              SIGNALILO_ICINGA_PASSWORD: kube.SecretKeyRef(secret, 'icinga_password'),
              SIGNALILO_ALERTMANAGER_BEARER_TOKEN: kube.SecretKeyRef(secret, 'alertmanager_token'),
            } + env_static_icinga_service_vars),
            ports_+: {
              http: { containerPort: 8888 },
            },
            livenessProbe: {
              httpGet: {
                path: '/healthz',
                port: 'http',
              },
            },
            readinessProbe: {
              httpGet: {
                path: '/healthz',
                port: 'http',
              },
            },
            resources: {
              requests: { cpu: '100m', memory: '64Mi' },
              limits: { cpu: '200m', memory: '128Mi' },
            },
          },
        },
      },
    },
  },
};

local service = kube.Service('signalilo') {
  metadata+: {
    namespace: params.namespace,
    labels+: {
      'app.kubernetes.io/name': 'signalilo',
      'app.kubernetes.io/instance': inv.parameters.cluster.name,
      'app.kubernetes.io/managed-by': 'syn',
    },
  },
  target_pod: deployment.spec.template,
  spec+: {
    ports: [
      {
        name: 'http',
        port: 80,
        targetPort: deployment.spec.template.spec.containers[0].ports[0].containerPort,
      },
    ],
  },
};

{
  '10_signalilo': [secret, deployment, service],
}
