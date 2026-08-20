"""
Vercel entry point for Pips Miner.

The persistent trading worker remains outside the serverless runtime.
This module exposes the existing Flask control API through Vercel.
"""

from backend.app import app

# Vercel's Python runtime discovers the Flask WSGI application as `app`.
