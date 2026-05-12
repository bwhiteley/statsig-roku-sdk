function LogEvent(name as string) as object
    return {
        "setValue": function(value as dynamic) as void
            m._value = value
        end function

        "setMetadata": function(metadata as object) as void
            m._metadata = metadata
        end function

        "setUser": function(user as object) as void
            m._user = user
        end function

        "toJson": function() as object
            payload = {
                "eventName": m._name
                value: m._value
                metadata: m._metadata
                time: m._time
                user: m._user
            }
            if (m._secondary_exposures <> invalid) then
                payload["secondaryExposures"] = m._secondary_exposures
            end if
            return payload
        end function

        "setSecondaryExposures": function(exposures as object) as void
            m._secondary_exposures = exposures
        end function

        _name: name
        _time: CreateObject("roDateTime").asSeconds() * 1000
        _value: invalid
        _metadata: invalid
        _user: invalid
        _secondary_exposures: invalid
    }
end function

function _hashName(name as String) as String
    return _hashNameSHA256(name)
end function

function _hashNameSHA256(name as String) as String
    ba1 = CreateObject("roByteArray")
    ba1.FromAsciiString(name)
    digest = CreateObject("roEVPDigest")
    digest.Setup("sha256")
    digest.Update(ba1)
    hash = digest.Final()

    ' base64 encode the hash
    ba2 = CreateObject("roByteArray") 
    ba2.FromHexString(hash)
    return ba2.ToBase64String()
end function

function _hashNameDJB2(name as String) as String
    ba = CreateObject("roByteArray")
    ba.FromAsciiString(name)

    hash = 0.0
    mod32 = 4294967296.0
    for each b in ba
        hash = (hash * 31.0 + b) mod mod32
    end for

    return _unsignedNumberToDecimalString(hash)
end function

function _unsignedNumberToDecimalString(value as dynamic) as String
    if value = invalid then
        return "0"
    end if

    remaining = value
    if remaining <= 0 then
        return "0"
    end if

    result = ""
    while remaining > 0
        digit = Int(remaining mod 10)
        result = Chr(48 + digit) + result
        remaining = Int(remaining / 10)
    end while

    return result
end function

function _isStringType(value as dynamic) as boolean
    valueType = type(value)
    return valueType = "String" or valueType = "roString"
end function

function _normalizeHashUsed(hashUsed as dynamic) as String
    if not _isStringType(hashUsed) then
        return "sha256"
    end if

    lowered = LCase(hashUsed)
    if lowered = "none" or lowered = "djb2" or lowered = "sha256" then
        return lowered
    end if

    return "sha256"
end function

function _hashNameByAlgorithm(name as String, hashUsed as dynamic) as String
    normalized = _normalizeHashUsed(hashUsed)
    if normalized = "none" then
        return name
    else if normalized = "djb2" then
        return _hashNameDJB2(name)
    end if

    return _hashNameSHA256(name)
end function

function _lookupByName(values as dynamic, name as String, hashUsed as dynamic) as dynamic
    if type(values) <> "roAssociativeArray" then
        return invalid
    end if

    value = values.Lookup(name)
    if value <> invalid then
        return value
    end if

    hashedName = _hashNameByAlgorithm(name, hashUsed)
    if hashedName = name then
        return invalid
    end if

    return values.Lookup(hashedName)
end function

function StatsigStore(logger as Object) as object
    this = {
        "checkGate": function(gateName as string) as boolean
            gate = _lookupByName(m._values.feature_gates, gateName, m._values["hash_used"])
            
            if (gate = invalid) then
                gate = {value: false, rule_id: "", secondary_exposures: []}
            endif

            m._logger.logGateExposure(gateName, gate.value, gate["rule_id"], gate["secondary_exposures"])
            return gate.value
        end function

        "getConfig": function(configName as string) as object
            config = _lookupByName(m._values.dynamic_configs, configName, m._values["hash_used"])
            if (config <> invalid) then
                dc = DynamicConfig(configName, config.value, config["rule_id"])
                dc._secondaryExposures = config.secondary_exposures
            else
                dc = DynamicConfig(configName, {}, "")
            endif

            m._logger.logConfigExposure(configName, dc._ruleID, dc._secondaryExposures)
            return dc
        end function

        "getExperiment": function(experiment as string) as object
            return m.getConfig(experiment)
        end function

        "getLayerParameter": function(layerName as string, parameterName as string, defaultValue as dynamic) as dynamic
            layer = _lookupByName(m._values.layer_configs, layerName, m._values["hash_used"])
            allocatedExperiment = ""
            isExplicitParameter = false
            secondaryExposures = []
            ruleID = ""

            if (layer <> invalid) then
                dc = DynamicConfig(layerName, layer.value, layer["rule_id"])
                dc._secondaryExposures = layer.secondary_exposures
                ruleID = dc._ruleID

                if _isStringType(layer["allocated_experiment_name"]) then
                    allocatedExperiment = layer["allocated_experiment_name"]
                end if
                if type(layer["explicit_parameters"]) = "roArray" then
                    for each explicitParam in layer["explicit_parameters"]
                        if explicitParam = parameterName then
                            isExplicitParameter = true
                            exit for
                        end if
                    end for
                end if
                if type(layer["parameter_rule_ids"]) = "roAssociativeArray" then
                    paramRuleID = layer["parameter_rule_ids"].Lookup(parameterName)
                    if _isStringType(paramRuleID) then
                        ruleID = paramRuleID
                    end if
                end if

                if isExplicitParameter then
                    if layer["secondary_exposures"] <> invalid then
                        secondaryExposures = layer["secondary_exposures"]
                    end if
                else
                    if layer["undelegated_secondary_exposures"] <> invalid then
                        secondaryExposures = layer["undelegated_secondary_exposures"]
                    else if layer["secondary_exposures"] <> invalid then
                        secondaryExposures = layer["secondary_exposures"]
                    end if
                end if
            else
                dc = DynamicConfig(layerName, {}, "")
            endif

            m._logger.logLayerExposure(layerName, parameterName, ruleID, secondaryExposures, allocatedExperiment, isExplicitParameter)
            return dc.get(parameterName, defaultValue)
        end function

        "getParameterStore": function(storeName as string) as object
            pStore = _lookupByName(m._values.param_stores, storeName, m._values["hash_used"])
            if (pStore = invalid) then
                pStore = {}
            end if

            return ParameterStore(storeName, pStore, m)
        end function

        clear: function() as void
            m._values = {
                feature_gates: {}
                dynamic_configs: {}
                layer_configs: {}
                param_stores: {}
                hash_used: "sha256"
            }
        end function

        save: function(data as object) as void
            defaultValues = {
                feature_gates: {}
                dynamic_configs: {}
                layer_configs: {}
                param_stores: {}
                hash_used: "sha256"
            }

            if data = invalid then
                m._values = defaultValues
                return
            end if

            if data["feature_gates"] <> invalid then
                defaultValues["feature_gates"] = data["feature_gates"]
            end if
            if data["dynamic_configs"] <> invalid then
                defaultValues["dynamic_configs"] = data["dynamic_configs"]
            end if
            if data["layer_configs"] <> invalid then
                defaultValues["layer_configs"] = data["layer_configs"]
            end if
            if data["param_stores"] <> invalid then
                defaultValues["param_stores"] = data["param_stores"]
            end if
            if _isStringType(data["hash_used"]) then
                defaultValues["hash_used"] = _normalizeHashUsed(data["hash_used"])
            end if

            m._values = defaultValues
        end function

        _values: {
            feature_gates: {}
            dynamic_configs: {}
            layer_configs: {}
            param_stores: {}
            hash_used: "sha256"
        }

        _logger: logger
    }

    return this
end function

function StatsigLogger(task) as object
    this = {
        "setUser": function(user as object) as void
            m._user = user.toLogDictionary()
        end function

        "log": function(event as object) as void
            m._task.event = {name: "log_event", payload: event.toJson()}
            return
        end function

        "logGateExposure": function(gate as string, value as boolean, ruleID as string, secondary as object) as void
            gateExposure = LogEvent("statsig::gate_exposure")
            gateExposure.setUser(m._user)
            strValue = "false"
            if value
                strValue = "true"
            end if
            gateExposure.setMetadata({
                gate: gate
                "gateValue": strValue
                "ruleID": ruleID
            })
            gateExposure.setSecondaryExposures(secondary)
            
            m.log(gateExposure)
        end function

        "logConfigExposure": function(config as string, ruleID as string, secondary as object) as void
            configExposure = LogEvent("statsig::config_exposure")
            configExposure.setUser(m._user)
            configExposure.setMetadata({
                config: config
                "ruleID": ruleID
            })
            configExposure.setSecondaryExposures(secondary)
            
            m.log(configExposure)
        end function

        "logLayerExposure": function(layer as string, parameter as string, ruleID as string, secondary as object, allocatedExperiment as string, isExplicitParameter as boolean) as void
            layerExposure = LogEvent("statsig::layer_exposure")
            layerExposure.setUser(m._user)
            explicitParamAsString = "false"
            if isExplicitParameter then
                explicitParamAsString = "true"
            end if
            layerExposure.setMetadata({
                config: layer
                "ruleID": ruleID
                "allocatedExperiment": allocatedExperiment
                "parameterName": parameter
                "isExplicitParameter": explicitParamAsString
            })
            layerExposure.setSecondaryExposures(secondary)

            m.log(layerExposure)
        end function

        "flush": function() as void
            if m._task <> invalid then
                m._task.event = {name: "flush"}
                return
            end if
        end function

        _user: invalid
        _task: task
    }
    return this
end function

function _Statsig_updateUser(user as Object) as void
    if (m._sdk_key = invalid) then
        return
    end if
    m._user = user
    m._logger.setUser(user)
    m._store.clear()
    initializeResult = m._network.initialize(user)
    m._store.save(initializeResult)
end function

function StatsigClient(task, user) as object
    this = {
        "checkGate": function(gateName as String) as boolean
            if (m._store = invalid) then
                return false
            end if
            res = m._store.checkGate(gateName)
            return res
        end function

        "getConfig": function(configName as String) as object
            if (m._store = invalid) then
                return DynamicConfig(configName, {}, "")
            end if
            return m._store.getConfig(configName)
        end function

        "getExperiment": function(experiment as String) as object
            if (m._store = invalid) then
                return DynamicConfig(experiment, {}, "")
            end if
            return m._store.getExperiment(experiment)
        end function

        "getParameterStore": function(storeName as String) as object
            if (m._store = invalid) then
                return ParameterStore(storeName, {}, invalid)
            end if
            return m._store.getParameterStore(storeName)
        end function

        "logEvent": function(eventName as String, value as Dynamic, metadata as object) as void
            if (m._logger = invalid) then
                return
            end if
            
            event = LogEvent(eventName)
            event.setValue(value)
            event.setMetadata(metadata)
            event.setUser(m._user)
        
            m._logger.log(event)
        end function

        "flush": function() as void
            m._logger.flush()
        end function

        "updateUser": function(user) as void
            m._user = user
            ' the pending logs are flushed in StatsigTask
            m._logger.setUser(user)
            m._store.clear()
        end function

        "loadValues": function(user as Object, initializeResult) as void
            if m._logger = invalid
                m._logger = StatsigLogger(m._task)
                m._logger.setUser(user)
                m._store = StatsigStore(m._logger)
            end if
            m._store.save(initializeResult)
        end function

        _user: user
        _logger: invalid
        _store: invalid
        _sdk_key: invalid
        _task: task
    }
    return this
end function