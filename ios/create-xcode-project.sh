#!/bin/bash
# Create Nexus iOS App Structure

BASE_DIR="Nexus"
mkdir -p "$BASE_DIR"/{Nexus,NexusWidget,NexusTests}
mkdir -p "$BASE_DIR/Nexus"/{Models,Views,ViewModels,Services,Utilities}
mkdir -p "$BASE_DIR/Nexus/Views"/{Food,Water,Weight,Mood,Dashboard}
mkdir -p "$BASE_DIR/Nexus/Assets.xcassets"

echo "✅ Created Nexus iOS project structure"
