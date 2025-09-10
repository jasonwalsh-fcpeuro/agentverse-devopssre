# Model Armor - Security & Observability Shield

## Architecture Overview

```mermaid
graph TB
    subgraph "Model Armor Security Layer"
        MA[Model Armor Core]
        PP[Prompt Protection]
        RG[Response Guard]
        AM[Audit Monitor]
    end
    
    subgraph "AI Agents"
        GA[Guardian Agent]
        VA[vLLM Agent]
        OA[Ollama Agent]
    end
    
    subgraph "Security Components"
        SM[Secret Manager]
        IAM[IAM Policies]
        VPC[VPC Security]
        FW[Firewall Rules]
    end
    
    subgraph "Observability"
        CT[Cloud Trace]
        CL[Cloud Logging]
        CM[Cloud Monitoring]
        AL[Alert Policies]
    end
    
    subgraph "Threat Detection"
        IDS[Input Sanitizer]
        OVS[Output Validator]
        RLD[Rate Limiter]
        TKB[Token Bucket]
    end
    
    GA --> MA
    VA --> MA
    OA --> MA
    
    MA --> PP
    MA --> RG
    MA --> AM
    
    PP --> IDS
    PP --> RLD
    RG --> OVS
    RG --> TKB
    
    AM --> CT
    AM --> CL
    AM --> CM
    
    MA --> SM
    MA --> IAM
    MA --> VPC
    
    CM --> AL
```

## Components

### 1. Prompt Protection
- Input validation and sanitization
- Injection attack prevention
- PII detection and masking
- Rate limiting per user/API key

### 2. Response Guard
- Output filtering for sensitive data
- Hallucination detection
- Content policy enforcement
- Token usage monitoring

### 3. Audit Monitor
- Request/response logging
- Security event tracking
- Performance metrics
- Compliance reporting

### 4. Security Integration
- Google Secret Manager for API keys
- IAM policies for access control
- VPC Service Controls
- Cloud Armor DDoS protection

## Implementation

The Model Armor system provides a security and observability layer for all AI agents in the AgentVerse infrastructure.