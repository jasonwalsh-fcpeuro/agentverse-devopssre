"""FastAPI middleware for Model Armor integration"""

import time
import uuid
from typing import Callable
from fastapi import Request, Response, HTTPException
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import Message

from modelarmor.armor import ModelArmor, ThreatLevel


class ModelArmorMiddleware(BaseHTTPMiddleware):
    """FastAPI middleware for Model Armor security"""
    
    def __init__(self, app, model_armor: ModelArmor):
        super().__init__(app)
        self.model_armor = model_armor
    
    async def dispatch(self, request: Request, call_next: Callable) -> Response:
        """Process request through Model Armor security checks"""
        
        # Generate request ID
        request_id = str(uuid.uuid4())
        request.state.request_id = request_id
        
        # Extract user ID (from header, JWT, or IP)
        user_id = self._extract_user_id(request)
        
        # Rate limiting check
        if not self.model_armor.check_rate_limit(user_id):
            return JSONResponse(
                status_code=429,
                content={
                    "error": "Rate limit exceeded",
                    "message": "Too many requests. Please try again later.",
                    "request_id": request_id
                }
            )
        
        # Process request
        start_time = time.time()
        
        try:
            # For POST requests with JSON body, validate prompt
            if request.method == "POST" and request.headers.get("content-type") == "application/json":
                body = await request.body()
                if body:
                    # Store body for later use
                    request.state.body = body
                    
                    # Validate prompt if present
                    import json
                    try:
                        data = json.loads(body)
                        if "prompt" in data:
                            valid, error = self.model_armor.validate_prompt(
                                data["prompt"], user_id
                            )
                            if not valid:
                                self.model_armor.log_security_event(
                                    event_type="blocked_request",
                                    threat_level=ThreatLevel.HIGH,
                                    source=user_id,
                                    details={"reason": error, "request_id": request_id}
                                )
                                return JSONResponse(
                                    status_code=400,
                                    content={
                                        "error": "Invalid request",
                                        "message": error,
                                        "request_id": request_id
                                    }
                                )
                    except json.JSONDecodeError:
                        pass
            
            # Process the request
            response = await call_next(request)
            
            # Log successful request
            elapsed_time = time.time() - start_time
            self.model_armor.log_security_event(
                event_type="request_processed",
                threat_level=ThreatLevel.SAFE,
                source=user_id,
                details={
                    "request_id": request_id,
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": response.status_code,
                    "elapsed_time": elapsed_time
                }
            )
            
            # Add security headers
            response.headers["X-Request-ID"] = request_id
            response.headers["X-Content-Type-Options"] = "nosniff"
            response.headers["X-Frame-Options"] = "DENY"
            response.headers["X-XSS-Protection"] = "1; mode=block"
            
            return response
            
        except Exception as e:
            # Log error
            self.model_armor.log_security_event(
                event_type="request_error",
                threat_level=ThreatLevel.MEDIUM,
                source=user_id,
                details={
                    "request_id": request_id,
                    "error": str(e),
                    "method": request.method,
                    "path": request.url.path
                }
            )
            
            return JSONResponse(
                status_code=500,
                content={
                    "error": "Internal server error",
                    "request_id": request_id
                }
            )
    
    def _extract_user_id(self, request: Request) -> str:
        """Extract user ID from request"""
        # Try API key header
        api_key = request.headers.get("X-API-Key")
        if api_key:
            return f"api_{api_key[:8]}"
        
        # Try Authorization header
        auth = request.headers.get("Authorization")
        if auth and auth.startswith("Bearer "):
            token = auth[7:]
            return f"bearer_{token[:8]}"
        
        # Fall back to IP address
        client_host = request.client.host if request.client else "unknown"
        return f"ip_{client_host}"