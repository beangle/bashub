create index idx_s6d9t6afcb79jfbamk81hj90m on bas.cfg_platform_feature_scripts (feature_id);
create index idx_j2s4cn47mq1a9qjtl9h44lo93 on bas.cfg_servers (farm_id);
create index idx_cfg_webapps_endpoints_webapp on bas.cfg_webapps_endpoints (webapp_id);
create index idx_cfg_webapps_endpoints_endpoint on bas.cfg_webapps_endpoints (endpoint_id);
create index idx_igjx23gjat79rj5lkvviauo60 on bas.cfg_webapps_targets (webapp_id);
create index idx_83jo3q4ran84y9bhcfn062qdo on bas.ems_menus (parent_id);
create index idx_8663nggim2n448wsyygff27s0 on bas.ems_menus_resources (menu_id);
create index idx_mon_server_samples_project_time on bas.mon_server_samples (project_id,sampled_at);
