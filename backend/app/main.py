from fastapi import FastAPI

from app.api import dev

app = FastAPI(title="GoSafe API", version="0.1.0")
app.include_router(dev.router)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}
