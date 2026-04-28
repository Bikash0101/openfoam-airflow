#!/bin/bash
# Pre-Simulation Validation Checklist for Stand Fan Office Airflow
# Run this script before executing ./Allrun
# Location: /home/bee17/CFD/airflow/validate_setup.sh

set -e

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   PRE-SIMULATION VALIDATION CHECKLIST                         ║"
echo "║   Stand Fan Office Airflow - OpenFOAM v2412                   ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Counter for checks
PASS=0
FAIL=0
WARN=0

check_pass() {
    echo "  ✓ PASS: $1"
    ((PASS++))
}

check_fail() {
    echo "  ✗ FAIL: $1"
    ((FAIL++))
}

check_warn() {
    echo "  ⚠ WARN: $1"
    ((WARN++))
}

# ============================================================================
# 1. DIRECTORY STRUCTURE CHECK
# ============================================================================
echo ""
echo "┌─ 1. DIRECTORY STRUCTURE ─────────────────────────────────────────┐"

if [ -d "system" ]; then
    check_pass "system/ directory exists"
else
    check_fail "system/ directory NOT FOUND"
    exit 1
fi

if [ -d "0" ]; then
    check_pass "0/ (initial conditions) directory exists"
else
    check_fail "0/ directory NOT FOUND"
    exit 1
fi

if [ -d "constant" ]; then
    check_pass "constant/ directory exists"
else
    check_fail "constant/ directory NOT FOUND"
    exit 1
fi

# ============================================================================
# 2. SYSTEM FILES CHECK
# ============================================================================
echo ""
echo "┌─ 2. SYSTEM CONFIGURATION FILES ──────────────────────────────────┐"

required_system_files=(
    "blockMeshDict"
    "controlDict"
    "createPatchDict"
    "fvSchemes"
    "fvSolution"
    "topoSetDict"
)

for file in "${required_system_files[@]}"; do
    if [ -f "system/$file" ]; then
        check_pass "system/$file exists"
    else
        check_fail "system/$file NOT FOUND"
    fi
done

# ============================================================================
# 3. INITIAL CONDITIONS CHECK
# ============================================================================
echo ""
echo "┌─ 3. INITIAL CONDITIONS (0/ directory) ───────────────────────────┐"

required_ic_files=(
    "U"
    "p"
)

for file in "${required_ic_files[@]}"; do
    if [ -f "0/$file" ]; then
        check_pass "0/$file exists"
    else
        check_fail "0/$file NOT FOUND"
    fi
done

# ============================================================================
# 4. FAN CONFIGURATION CHECK
# ============================================================================
echo ""
echo "┌─ 4. FAN CONFIGURATION ───────────────────────────────────────────┐"

# Check topoSetDict for searchableDisk
if grep -q "searchableDisk" system/topoSetDict; then
    check_pass "system/topoSetDict contains searchableDisk definition"
else
    check_fail "system/topoSetDict missing searchableDisk"
fi

# Check fan origin in topoSetDict
if grep -q "origin" system/topoSetDict; then
    fan_origin=$(grep -A2 "origin" system/topoSetDict | head -1)
    check_pass "Fan origin defined: $fan_origin"
else
    check_warn "Fan origin not explicitly found (may be using default)"
fi

# Check fan radius in topoSetDict
if grep -q "radius  0.2" system/topoSetDict; then
    check_pass "Fan radius set to 0.2m (0.4m diameter)"
else
    check_warn "Fan radius may not be 0.2m - check topoSetDict"
fi

# Check createPatchDict exists and has cyclic fan patch
if [ -f "system/createPatchDict" ]; then
    check_pass "system/createPatchDict exists"
    if grep -q "patchType   cyclic" system/createPatchDict; then
        check_pass "createPatchDict configures cyclic patch type"
    else
        check_fail "createPatchDict missing cyclic patchType"
    fi
else
    check_fail "system/createPatchDict NOT FOUND"
fi

# ============================================================================
# 5. BOUNDARY CONDITIONS CHECK
# ============================================================================
echo ""
echo "┌─ 5. BOUNDARY CONDITIONS ─────────────────────────────────────────┐"

# Check p field for fan BC
if grep -q "fan" 0/p; then
    check_pass "0/p contains fan boundary condition"
    if grep -A3 "^    fan$" 0/p | grep -q "type.*fan"; then
        check_pass "Fan BC type set to 'fan' in 0/p"
    else
        check_fail "Fan BC type not correctly set in 0/p"
    fi
else
    check_fail "0/p missing fan boundary condition"
fi

# Check p field for pressure jump coefficient
if grep -q "f.*uniform.*4" 0/p; then
    check_pass "Pressure jump coefficient f defined in 0/p"
else
    check_warn "Pressure jump coefficient f may not be set (check 0/p)"
fi

# Check U field for cyclic BC
if grep -q "fan" 0/U; then
    check_pass "0/U contains fan boundary condition"
    if grep -A1 "^    fan$" 0/U | grep -q "type.*cyclic"; then
        check_pass "Fan velocity BC type set to 'cyclic' in 0/U"
    else
        check_fail "Fan velocity BC type not 'cyclic' in 0/U"
    fi
else
    check_fail "0/U missing fan boundary condition"
fi

# ============================================================================
# 6. NUMERICAL SCHEMES CHECK
# ============================================================================
echo ""
echo "┌─ 6. NUMERICAL SCHEMES ───────────────────────────────────────────┐"

# Check fvSchemes for momentum convection
if grep -q "div(phi,U)" system/fvSchemes; then
    check_pass "div(phi,U) scheme defined in fvSchemes"
else
    check_fail "div(phi,U) scheme missing in fvSchemes"
fi

# Check fvSchemes does NOT have turbulence schemes
if ! grep -q "div(phi,k)" system/fvSchemes; then
    check_pass "No turbulence (k) scheme in fvSchemes (correct)"
else
    check_warn "fvSchemes contains div(phi,k) - should be removed"
fi

if ! grep -q "div(phi,omega)" system/fvSchemes; then
    check_pass "No turbulence (omega) scheme in fvSchemes (correct)"
else
    check_warn "fvSchemes contains div(phi,omega) - should be removed"
fi

# ============================================================================
# 7. SOLVER CONFIGURATION CHECK
# ============================================================================
echo ""
echo "┌─ 7. SOLVER CONFIGURATION ────────────────────────────────────────┐"

# Check fvSolution for PIMPLE
if grep -q "PIMPLE" system/fvSolution; then
    check_pass "PIMPLE algorithm configured in fvSolution"
else
    check_fail "PIMPLE algorithm NOT FOUND in fvSolution"
fi

# Check PIMPLE outer loops >= 3
if grep -q "nOuterCorrectors.*3" system/fvSolution; then
    check_pass "PIMPLE: nOuterCorrectors = 3 (good for fan pressure jump)"
elif grep -q "nOuterCorrectors.*[1-2]" system/fvSolution; then
    check_warn "PIMPLE: nOuterCorrectors < 3 (may underpredict fan pressure jump)"
else
    check_fail "nOuterCorrectors not found or invalid in fvSolution"
fi

# Check pressure solver
if grep -q "solver.*GAMG" system/fvSolution; then
    check_pass "Pressure solver set to GAMG (multigrid)"
else
    check_warn "Pressure solver not GAMG - verify in fvSolution"
fi

# Check velocity solver
if grep -q "U.*solver.*PBiCG" system/fvSolution || grep -q "U.*solver.*smoothSolver" system/fvSolution; then
    check_pass "Velocity solver configured"
else
    check_warn "Velocity solver not clearly defined - check fvSolution"
fi

# ============================================================================
# 8. TIME STEPPING CHECK
# ============================================================================
echo ""
echo "┌─ 8. TIME STEPPING CONFIGURATION ────────────────────────────────┐"

# Check controlDict for solver type
if grep -q "solver.*incompressibleFluid" system/controlDict; then
    check_pass "Solver set to incompressibleFluid"
else
    check_fail "Solver NOT set to incompressibleFluid"
fi

# Check time step
if grep -q "deltaT.*0.0[0-1]" system/controlDict; then
    deltaT=$(grep "deltaT" system/controlDict | grep -oE "0\.[0-9]+")
    check_pass "Time step set to $deltaT seconds (stable)"
elif grep -q "deltaT.*0\.[0-9]" system/controlDict; then
    deltaT=$(grep "deltaT" system/controlDict | grep -oE "0\.[0-9]+")
    check_warn "Time step may be large: $deltaT seconds (verify CFL < 1)"
else
    check_fail "deltaT not found in controlDict"
fi

# Check adjustTimeStep
if grep -q "adjustTimeStep.*yes" system/controlDict; then
    check_pass "adjustTimeStep enabled (auto time-step control)"
else
    check_warn "adjustTimeStep not enabled (may need manual control)"
fi

# Check simulation duration
if grep -q "endTime.*[0-9]" system/controlDict; then
    endTime=$(grep "endTime" system/controlDict | grep -oE "[0-9]+")
    check_pass "Simulation duration: $endTime seconds"
fi

# ============================================================================
# 9. POST-PROCESSING FUNCTIONS CHECK
# ============================================================================
echo ""
echo "┌─ 9. POST-PROCESSING FUNCTIONS ──────────────────────────────────┐"

# Check for probes function
if grep -q "probes" system/controlDict; then
    check_pass "Probes function object configured (monitoring jets)"
else
    check_warn "Probes function not found - manual sampling may be needed"
fi

# Check for residuals function
if grep -q "residuals" system/controlDict; then
    check_pass "Residuals function object configured (convergence tracking)"
else
    check_warn "Residuals function not found"
fi

# ============================================================================
# 10. ALLRUN SCRIPT CHECK
# ============================================================================
echo ""
echo "┌─ 10. EXECUTION SCRIPT ───────────────────────────────────────────┐"

if [ -f "Allrun" ]; then
    check_pass "Allrun script exists"
    if [ -x "Allrun" ]; then
        check_pass "Allrun script is executable"
    else
        check_warn "Allrun script is not executable - run: chmod +x Allrun"
    fi
    
    if grep -q "topoSet" Allrun; then
        check_pass "Allrun includes topoSet step"
    else
        check_fail "Allrun missing topoSet step"
    fi
    
    if grep -q "createPatch" Allrun; then
        check_pass "Allrun includes createPatch step"
    else
        check_fail "Allrun missing createPatch step"
    fi
    
    if grep -q "foamRun" Allrun; then
        check_pass "Allrun includes foamRun step"
    else
        check_fail "Allrun missing foamRun step"
    fi
else
    check_fail "Allrun script NOT FOUND"
fi

# ============================================================================
# SUMMARY
# ============================================================================
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    VALIDATION SUMMARY                         ║"
echo "╠════════════════════════════════════════════════════════════════╣"
echo "  ✓ PASS:  $PASS"
echo "  ✗ FAIL:  $FAIL"
echo "  ⚠ WARN:  $WARN"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "✓ All critical checks PASSED!"
    echo ""
    if [ $WARN -eq 0 ]; then
        echo "Ready to run: ./Allrun"
    else
        echo "Ready to run: ./Allrun (but review warnings above)"
    fi
    exit 0
else
    echo "✗ FAILED checks detected - fix issues before running ./Allrun"
    exit 1
fi

# ========================================================================
