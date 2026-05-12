function ParameterStore(name as String, configuration as dynamic, store as dynamic) as object
    if type(configuration) <> "roAssociativeArray" then
        configuration = {}
    end if

    return {
        "get": function(key as string, defaultValue as dynamic) as dynamic
            if key = invalid then
                return defaultValue
            end if

            param = m._configuration.Lookup(key)
            if not m._isAssociativeArray(param) then
                return defaultValue
            end if

            refType = param.Lookup("ref_type")
            paramType = param.Lookup("param_type")
            if not m._isString(refType) or not m._isString(paramType) then
                return defaultValue
            end if
            normalizedRefType = LCase(refType)
            normalizedParamType = LCase(paramType)

            expectedType = m._inferParamType(defaultValue)
            if expectedType <> "unknown" and expectedType <> normalizedParamType then
                return defaultValue
            end if

            value = invalid
            if normalizedRefType = "static" then
                value = param.Lookup("value")
            else if normalizedRefType = "gate" then
                value = m._evaluateGate(param)
            else if normalizedRefType = "dynamic_config" then
                value = m._evaluateConfig(param, defaultValue)
            else if normalizedRefType = "experiment" then
                value = m._evaluateExperiment(param, defaultValue)
            else if normalizedRefType = "layer" then
                value = m._evaluateLayer(param, defaultValue)
            else
                return defaultValue
            end if

            if m._isTypeCompatible(value, normalizedParamType) then
                return value
            end if

            return defaultValue
        end function

        "getString": function(key as string, defaultValue as string) as string
            return m.get(key, defaultValue)
        end function

        "getBoolean": function(key as string, defaultValue as boolean) as boolean
            return m.get(key, defaultValue)
        end function

        "getNumber": function(key as string, defaultValue as dynamic) as dynamic
            return m.get(key, defaultValue)
        end function

        "getDouble": function(key as string, defaultValue as dynamic) as dynamic
            return m.get(key, defaultValue)
        end function

        "getObject": function(key as string, defaultValue as object) as object
            return m.get(key, defaultValue)
        end function

        "getDictionary": function(key as string, defaultValue as object) as object
            return m.get(key, defaultValue)
        end function

        "getArray": function(key as string, defaultValue as object) as object
            return m.get(key, defaultValue)
        end function

        "getKeys": function() as object
            keys = []
            for each key in m._configuration
                keys.push(key)
            end for
            return keys
        end function

        "getName": function() as string
            return m._name
        end function

        "_evaluateGate": function(param as object) as dynamic
            if m._store = invalid then
                return invalid
            end if

            gateName = param.Lookup("gate_name")
            passValue = param.Lookup("pass_value")
            failValue = param.Lookup("fail_value")
            if not m._isString(gateName) then
                return invalid
            end if
            if passValue = invalid or failValue = invalid then
                return invalid
            end if

            passes = m._store.checkGate(gateName)
            if passes then
                return passValue
            else
                return failValue
            end if
        end function

        "_evaluateConfig": function(param as object, defaultValue as dynamic) as dynamic
            if m._store = invalid then
                return defaultValue
            end if

            configName = param.Lookup("config_name")
            paramName = param.Lookup("param_name")
            if not m._isString(configName) or not m._isString(paramName) then
                return defaultValue
            end if

            config = m._store.getConfig(configName)
            if config = invalid then
                return defaultValue
            end if
            return config.get(paramName, defaultValue)
        end function

        "_evaluateExperiment": function(param as object, defaultValue as dynamic) as dynamic
            if m._store = invalid then
                return defaultValue
            end if

            experimentName = param.Lookup("experiment_name")
            paramName = param.Lookup("param_name")
            if not m._isString(experimentName) or not m._isString(paramName) then
                return defaultValue
            end if

            experiment = m._store.getExperiment(experimentName)
            if experiment = invalid then
                return defaultValue
            end if
            return experiment.get(paramName, defaultValue)
        end function

        "_evaluateLayer": function(param as object, defaultValue as dynamic) as dynamic
            if m._store = invalid then
                return defaultValue
            end if

            layerName = param.Lookup("layer_name")
            paramName = param.Lookup("param_name")
            if not m._isString(layerName) or not m._isString(paramName) then
                return defaultValue
            end if

            return m._store.getLayerParameter(layerName, paramName, defaultValue)
        end function

        "_inferParamType": function(value as dynamic) as string
            valueType = type(value)
            if value = invalid then
                return "unknown"
            else if m._isBoolean(value) then
                return "boolean"
            else if m._isString(value) then
                return "string"
            else if m._isNumber(value) then
                return "number"
            else if m._isAssociativeArray(value) then
                return "object"
            else if m._isArray(value) then
                return "array"
            end if
            return "unknown"
        end function

        "_isTypeCompatible": function(value as dynamic, paramType as string) as boolean
            if value = invalid then
                return false
            end if

            if paramType = "boolean" then
                return m._isBoolean(value)
            else if paramType = "string" then
                return m._isString(value)
            else if paramType = "number" then
                return m._isNumber(value)
            else if paramType = "object" then
                return m._isAssociativeArray(value)
            else if paramType = "array" then
                return m._isArray(value)
            end if

            return false
        end function

        "_isNumber": function(value as dynamic) as boolean
            valueType = type(value)
            return valueType = "Integer" or valueType = "LongInteger" or valueType = "Float" or valueType = "Double" or valueType = "roInteger" or valueType = "roLongInteger" or valueType = "roFloat" or valueType = "roDouble" or valueType = "roInt"
        end function

        "_isString": function(value as dynamic) as boolean
            valueType = type(value)
            return valueType = "String" or valueType = "roString"
        end function

        "_isBoolean": function(value as dynamic) as boolean
            valueType = type(value)
            return valueType = "Boolean" or valueType = "roBoolean"
        end function

        "_isAssociativeArray": function(value as dynamic) as boolean
            return type(value) = "roAssociativeArray"
        end function

        "_isArray": function(value as dynamic) as boolean
            valueType = type(value)
            return valueType = "roArray" or valueType = "Array"
        end function

        _name: name
        _configuration: configuration
        _store: store
    }
end function
