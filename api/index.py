"""
Vercel entry point for Pips Miner.

The persistent trading worker remains outside the serverless runtime.
This module exposes the existing Flask control API through Vercel.
"""

from backend.app import app
import backend.broker_search  # noqa: F401 - registers broker search route

# Vercel's Python runtime discovers the Flask WSGI application as `app`.
