from __future__ import annotations

from pydantic import BaseModel


class PolicyDocumentSummary(BaseModel):
    slug: str
    title: str


class PolicyIndex(BaseModel):
    version: int
    documents: list[PolicyDocumentSummary]


class PolicyDocument(BaseModel):
    slug: str
    title: str
    version: int
    body: str
