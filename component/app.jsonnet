local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.signalilo;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('signalilo', params.namespace);

{
  signalilo: app,
}
