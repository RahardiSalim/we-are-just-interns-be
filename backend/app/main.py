from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import dev, incidents, me, trips

app = FastAPI(title="GoSafe API", version="0.1.0")
# Auth is a bearer token, not cookies, so any origin may call; the token is the gate.
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
app.include_router(me.router)
app.include_router(trips.router)
app.include_router(incidents.router)
app.include_router(dev.router)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}
