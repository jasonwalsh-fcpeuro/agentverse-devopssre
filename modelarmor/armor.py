"""Model Armor - Core security and observability module"""

import logging
import time
import hashlib
import json
from typing import Dict, Any, Optional, List
from datetime import datetime, timedelta
from collections import defaultdict
from dataclasses import dataclass, field
from enum import Enum

from pydantic import BaseModel, Field
from opentelemetry import trace
from opentelemetry.trace import Status, StatusCode
from google.cloud import logging as cloud_logging
from google.cloud import secretmanager

logger = logging.getLogger(__name__)


class ThreatLevel(Enum):
    """Threat level classifications"""
    SAFE = "safe"
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


class SecurityEvent(BaseModel):
    """Security event model"""
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    event_type: str
    threat_level: ThreatLevel
    source: str
    details: Dict[str, Any]
    mitigated: bool = False


@dataclass
class RateLimitConfig:
    """Rate limiting configuration"""
    requests_per_minute: int = 60
    requests_per_hour: int = 1000
    token_bucket_size: int = 100
    token_refill_rate: float = 1.0


@dataclass
class TokenBucket:
    """Token bucket for rate limiting"""
    capacity: int
    tokens: float = field(default=0.0)
    last_refill: float = field(default_factory=time.time)
    refill_rate: float = 1.0
    
    def __post_init__(self):
        self.tokens = float(self.capacity)
    
    def consume(self, tokens: int = 1) -> bool:
        """Attempt to consume tokens"""
        self.refill()
        if self.tokens >= tokens:
            self.tokens -= tokens
            return True
        return False
    
    def refill(self):
        """Refill tokens based on elapsed time"""
        now = time.time()
        elapsed = now - self.last_refill
        self.tokens = min(
            self.capacity,
            self.tokens + (elapsed * self.refill_rate)
        )
        self.last_refill = now


class ModelArmor:
    """Core Model Armor security system"""
    
    def __init__(
        self,
        project_id: str,
        enable_cloud_logging: bool = True,
        rate_limit_config: Optional[RateLimitConfig] = None
    ):
        self.project_id = project_id
        self.rate_limit_config = rate_limit_config or RateLimitConfig()
        self.rate_limiters: Dict[str, TokenBucket] = defaultdict(
            lambda: TokenBucket(
                capacity=self.rate_limit_config.token_bucket_size,
                refill_rate=self.rate_limit_config.token_refill_rate
            )
        )
        
        # Initialize Cloud Logging
        if enable_cloud_logging:
            self.cloud_logger = cloud_logging.Client(project=project_id).logger("model-armor")
        else:
            self.cloud_logger = None
        
        # Initialize tracer
        self.tracer = trace.get_tracer(__name__)
        
        # Security patterns
        self.injection_patterns = [
            "ignore previous instructions",
            "disregard all prior",
            "system prompt",
            "you are now",
            "act as if",
            "pretend to be",
        ]
        
        self.sensitive_patterns = [
            r"\b\d{3}-\d{2}-\d{4}\b",  # SSN
            r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b",  # Email
            r"\b(?:\d{4}[-\s]?){3}\d{4}\b",  # Credit card
            r"\bsk-[a-zA-Z0-9]{48}\b",  # API keys
        ]
        
        self.security_events: List[SecurityEvent] = []
    
    def check_rate_limit(self, user_id: str) -> bool:
        """Check if request is within rate limits"""
        with self.tracer.start_as_current_span("rate_limit_check") as span:
            span.set_attribute("user_id", user_id)
            
            bucket = self.rate_limiters[user_id]
            allowed = bucket.consume()
            
            span.set_attribute("rate_limit.allowed", allowed)
            span.set_attribute("rate_limit.tokens_remaining", bucket.tokens)
            
            if not allowed:
                self.log_security_event(
                    event_type="rate_limit_exceeded",
                    threat_level=ThreatLevel.MEDIUM,
                    source=user_id,
                    details={"tokens_remaining": bucket.tokens}
                )
            
            return allowed
    
    def validate_prompt(self, prompt: str, user_id: str) -> tuple[bool, Optional[str]]:
        """Validate prompt for security threats"""
        with self.tracer.start_as_current_span("prompt_validation") as span:
            span.set_attribute("user_id", user_id)
            span.set_attribute("prompt_length", len(prompt))
            
            # Check for injection attempts
            prompt_lower = prompt.lower()
            for pattern in self.injection_patterns:
                if pattern in prompt_lower:
                    self.log_security_event(
                        event_type="injection_attempt",
                        threat_level=ThreatLevel.HIGH,
                        source=user_id,
                        details={"pattern": pattern, "prompt_hash": self._hash_text(prompt)}
                    )
                    span.set_status(Status(StatusCode.ERROR, "Injection detected"))
                    return False, f"Potential injection detected: {pattern}"
            
            # Check prompt length
            if len(prompt) > 10000:
                self.log_security_event(
                    event_type="excessive_prompt_length",
                    threat_level=ThreatLevel.LOW,
                    source=user_id,
                    details={"length": len(prompt)}
                )
                span.set_status(Status(StatusCode.ERROR, "Prompt too long"))
                return False, "Prompt exceeds maximum length"
            
            span.set_status(Status(StatusCode.OK))
            return True, None
    
    def validate_response(self, response: str, user_id: str) -> tuple[bool, Optional[str]]:
        """Validate model response for sensitive data"""
        with self.tracer.start_as_current_span("response_validation") as span:
            span.set_attribute("user_id", user_id)
            span.set_attribute("response_length", len(response))
            
            # Check for sensitive data patterns
            import re
            for pattern in self.sensitive_patterns:
                if re.search(pattern, response):
                    self.log_security_event(
                        event_type="sensitive_data_leak",
                        threat_level=ThreatLevel.CRITICAL,
                        source=user_id,
                        details={"pattern_type": pattern[:20], "response_hash": self._hash_text(response)}
                    )
                    span.set_status(Status(StatusCode.ERROR, "Sensitive data detected"))
                    return False, "Response contains sensitive information"
            
            span.set_status(Status(StatusCode.OK))
            return True, None
    
    def log_security_event(
        self,
        event_type: str,
        threat_level: ThreatLevel,
        source: str,
        details: Dict[str, Any]
    ):
        """Log security event"""
        event = SecurityEvent(
            event_type=event_type,
            threat_level=threat_level,
            source=source,
            details=details
        )
        
        self.security_events.append(event)
        
        # Log to Cloud Logging
        if self.cloud_logger:
            self.cloud_logger.log_struct({
                "timestamp": event.timestamp.isoformat(),
                "event_type": event.event_type,
                "threat_level": event.threat_level.value,
                "source": event.source,
                "details": event.details
            }, severity=self._threat_to_severity(threat_level))
        
        # Log locally
        logger.warning(f"Security Event: {event.model_dump_json()}")
    
    def get_security_metrics(self) -> Dict[str, Any]:
        """Get security metrics summary"""
        now = datetime.utcnow()
        last_hour = now - timedelta(hours=1)
        
        recent_events = [e for e in self.security_events if e.timestamp > last_hour]
        
        threat_counts = defaultdict(int)
        for event in recent_events:
            threat_counts[event.threat_level.value] += 1
        
        return {
            "total_events_last_hour": len(recent_events),
            "threat_level_distribution": dict(threat_counts),
            "active_rate_limiters": len(self.rate_limiters),
            "timestamp": now.isoformat()
        }
    
    @staticmethod
    def _hash_text(text: str) -> str:
        """Generate hash of text for logging"""
        return hashlib.sha256(text.encode()).hexdigest()[:16]
    
    @staticmethod
    def _threat_to_severity(threat_level: ThreatLevel) -> str:
        """Convert threat level to Cloud Logging severity"""
        mapping = {
            ThreatLevel.SAFE: "INFO",
            ThreatLevel.LOW: "NOTICE",
            ThreatLevel.MEDIUM: "WARNING",
            ThreatLevel.HIGH: "ERROR",
            ThreatLevel.CRITICAL: "CRITICAL"
        }
        return mapping.get(threat_level, "DEFAULT")