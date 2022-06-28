param location string = resourceGroup().location
var _resourceName =  uniqueString(deployment().name)
param logStorageRetentionDays int = 7

var _subnets = [
  {
    name: 'snet-001-service-runtime'
    addressPrefix: '10.1.0.0/24'
  }
  {
    name: 'snet-002-apps'
    addressPrefix: '10.1.1.0/24'
  }
]

resource springCloudVnet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: 'spring-apps-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [for item in _subnets: {
      name: item.name
      properties: {
        addressPrefix: item.addressPrefix
      }
    }]
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2019-09-01' = {
  name: '${_resourceName}-kv'
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    enabledForTemplateDeployment: true
    enableSoftDelete: false
    enableRbacAuthorization: true
  }
}


// Azure Spring Apps requires Owner permission to your virtual network
resource vnetOwnerRole 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = {
  name: guid(subscription().id, springCloudVnet.id, 'Owner')
  scope: springCloudVnet
  properties: {
    principalId: '60e9da4f-fc61-418c-95bf-de7c51ed79b9' // Azure Spring Cloud Resource Provider
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8e3af657-a8ff-443c-a75c-2fe8c4bcb635')
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: 'spring-log-analytics-workspace'
  location: location
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'adam-spring-app-insights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Bluefield'
    Request_Source: 'rest'
    WorkspaceResourceId: logAnalyticsWorkspace.id
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2021-05-01' existing = {
  name: last(split(springCloudVnet.id, '/'))

  resource subnet1 'subnets' existing = {
    name: 'snet-001-service-runtime'
  }

  resource subnet2 'subnets' existing = {
    name: 'snet-002-apps'
  }

}

resource springCloudInstance 'Microsoft.AppPlatform/Spring@2022-05-01-preview' = {
  name: 'adam-spring-cloud-instance'
  location: location
  sku:{
    name: 'S0'
    tier: 'Standard'
  }
  properties: {
    zoneRedundant: false
    networkProfile: {
      serviceCidr: '10.0.0.0/16,10.2.0.0/16,10.3.0.1/16'
      serviceRuntimeSubnetId: vnet::subnet1.id
      appSubnetId: vnet::subnet2.id
    }
    vnetAddons: {
      logStreamPublicEndpoint: false
    }
  }

  resource spingCloudMonitoringSettings 'monitoringSettings@2022-05-01-preview' = {
    name: 'default'
    properties: {
      traceEnabled: true
      appInsightsInstrumentationKey: appInsights.properties.InstrumentationKey
      appInsightsSamplingRate: 10
    }
  }
}


resource springCloudDiagnosticsSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'monitoring'
  scope: springCloudInstance
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: [
      {
        category: 'ApplicationConsole'
        enabled: true
        retentionPolicy: {
          days: logStorageRetentionDays
          enabled: false
        }
      }
      {
        category: 'SystemLogs'
        enabled: true
        retentionPolicy: {
          days: logStorageRetentionDays
          enabled: false
        }
      }
      {
        category: 'IngressLogs'
        enabled: true
        retentionPolicy: {
          days: logStorageRetentionDays
          enabled: false
        }
      }
      {
        category: 'BuildLogs'
        enabled: true
        retentionPolicy: {
          days: logStorageRetentionDays
          enabled: false
        }
      }
      {
        category: 'ContainerEventLogs'
        enabled: true
        retentionPolicy: {
          days: logStorageRetentionDays
          enabled: false
        }
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}
