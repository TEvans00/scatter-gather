ruleset manage_sensors {
  meta {
    name "Manage Sensors"
    description <<
      Manages a collection of temperature sensors
    >>
    author "Tyla Evans"
    provides sensors, temperatures
    shares sensors, temperatures
    use module io.picolabs.wrangler alias wrangler
    use module io.picolabs.subscription alias subs
  }

  global {
    default_threshold = 78

    sensors = function() {
      subs:established().filter(
        function(sub){
          sub{"Tx_role"} == "sensor"
        }
      ).map(
        function(sensor){
          eci = sensor{"Tx"}.klog("eci:")
          host = (sensor{"Tx_host"}.defaultsTo(meta:host)).klog("host:")
          profile = wrangler:picoQuery(eci,"sensor_profile","profile",{},host).klog("profile:")
          info = sensor.put("name", profile{"name"})
          info
        }
      )
    }

    temperatures = function() {
      return sensors().reduce(
        function(acc, sensor){
          eci = sensor{"Tx"}.klog("eci:")
          host = (sensor{"Tx_host"}.defaultsTo(meta:host)).klog("host:")
          name = sensor{"name"}.klog("name:")
          temperatures = wrangler:picoQuery(eci,"temperature_store","temperatures",{}, host).klog("temperatures:")
          return acc.put(eci, {"name": name, "temperatures": temperatures})
        }, {})
    }
  }

  rule intialization {
    select when wrangler ruleset_installed where event:attrs{"rids"} >< meta:rid
    always {
      ent:eci_to_name := {}
    }
  }

  rule create_sensor {
    select when sensor new_sensor
    pre {
      name = event:attrs{"name"}.klog("name:")
    }
    send_directive("initializing_sensor", {"sensor_name":name})
    always {
      raise wrangler event "new_child_request"
        attributes { "name": name,
                     "backgroundColor": "#13A169" }
    }
  }

  rule store_sensor_name {
    select when wrangler new_child_created
    pre {
      eci = event:attrs{"eci"}.klog("eci:")
      name = event:attrs{"name"}.klog("name:")
    }
    if eci && name then noop()
    fired {
      ent:eci_to_name{eci} := name
    }
  }

  rule trigger_sensor_installation {
    select when wrangler new_child_created
    pre {
      eci = event:attrs{"eci"}.klog("eci:")
    }
    if eci then
      event:send(
        { "eci": eci,
          "eid": "install-ruleset",
          "domain": "wrangler",
          "type": "install_ruleset_request",
          "attrs": {
            "absoluteURL": meta:rulesetURI,
            "rid": "sensor_installer"
          }
        }
      )
  }

  rule introduce_sensor {
    select when sensor introduction
      wellKnown_eci re#(.+)#
      setting(wellKnown_eci)
      pre {
        host = event:attrs{"host"}
      }
      if host && host != "" then noop()
      fired {
        raise sensor event "subscription_request" attributes {
          "wellKnown_eci": wellKnown_eci,
          "host": host
        }
      } else {
        raise sensor event "subscription_request" attributes {
          "wellKnown_eci": wellKnown_eci
        }
      }
  }

  rule initiate_subscription_to_child_sensor {
    select when sensor_installer installation_finished
      wellKnown_eci re#(.+)#
      setting(wellKnown_eci)
    always {
      raise sensor event "subscription_request" attributes {
        "wellKnown_eci": wellKnown_eci
      }
    }
  }

  rule subscribe_to_sensor {
    select when sensor subscription_request
      wellKnown_eci re#(.+)#
      setting(wellKnown_eci)
    pre {
      host = event:attrs{"host"}
    }
    always {
      raise wrangler event "subscription" attributes {
        "wellKnown_Tx": wellKnown_eci,
        "Rx_role":"manager",
        "Tx_role":"sensor",
        "Tx_host": host || meta:host
      }
    }
  }

  rule initialize_sensor_profile {
    select when sensor_installer installation_finished
    pre {
      eci = event:attrs{"child_eci"}.klog("eci:")
      name = ent:eci_to_name{eci}.klog("name:")
    }
    if name then
      event:send({
        "eci": eci,
        "domain": "sensor",
        "type": "profile_updated",
        "attrs": {
          "name": name,
          "temperature_threshold": default_threshold,
        }
      })
  }

  rule delete_sensor {
    select when sensor unneeded_sensor
    pre {
      name = event:attrs{"name"}.klog("name:")
      sensor = ent:eci_to_name.filter(function(v,k){ v == name}).klog("sensor:")
      eci = sensor.keys()[0].klog("eci:")
    }
    if eci then
      send_directive("deleting_sensor", {"sensor_name":name})
    fired {
      raise wrangler event "child_deletion_request"
        attributes {"eci": eci};
      clear ent:eci_to_name{eci}
    }
  }
}
