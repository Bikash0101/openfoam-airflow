# OpenFOAM Stand Fan Simulation - Configuration Summary

## Task Completion Status

✅ **COMPLETED**: Adapted roomResidenceTime case for 0.4m stand fan in office with partition walls

---

## Files Modified/Created

### 1. **system/topoSetDict** ✏️ MODIFIED
**Change**: Added fan disc definition using searchableDisk geometry
- **Fan location**: (1.5, 0.9, 0.9) m (office center - adjust to your fan position)
- **Fan diameter**: 0.4 m (radius 0.2 m)
- **Orientation**: Normal vector (1, 0, 0) - discharge along +X axis
- **Mesh operation**: searchableSurfaceToFace creates circular disc faceSet
- **Conversion**: faceSet → faceZoneSet for patch creation

### 2. **system/createPatchDict** ✨ NEW
**Purpose**: Convert fan faceZone into cyclic boundary patch
- **Patch type**: cyclic (enables suction on rear + discharge on front)
- **Patch name**: fan
- **Construction**: From faceZones (fanZone)
- **Match tolerance**: 1e-3 (auto-detect orientation)

### 3. **0/p** ✏️ MODIFIED
**Previous**: fan_inlet (fixedValue 0), fan_outlet (zeroGradient)  
**Now**: Single cyclic fan patch with pressure jump BC

```cpp
fan
{
    type            fan;
    patchType       cyclic;
    f               uniform 4.17;      // Pressure rise coefficient
    phi             phi;               // Flux field (v2412 unified)
    rho             rho;               // Density field (v2412 unified)
}
```

**Physics**:  
- $\Delta p_{\text{fan}} = f \times \frac{1}{2} \rho U^2 = 4.17 \times 0.5 \times 1.2 \times 4 \approx 10$ Pa
- Pressure rises 10 Pa across fan disc (typical stand fan)
- f-coefficient is dimensionless, can be made velocity-dependent

### 4. **0/U** ✏️ MODIFIED
**Previous**: fan_inlet (fixedValue (2 0 0)), fan_outlet (zeroGradient)  
**Now**: Single cyclic boundary matching pressure patch

```cpp
fan
{
    type            cyclic;
}
```

**Physics**:
- Cyclic BC allows bidirectional flow (suction rear + discharge front)
- No explicit velocity prescribed; solver couples U with pressure jump
- Velocity profile develops naturally from pressure solver

### 5. **system/fvSchemes** ✏️ MODIFIED
**Removed**: 
- `div(phi,k)` (turbulent kinetic energy)
- `div(phi,omega)` (specific dissipation rate)

**Retained**:
- `div(phi,U)` - upwind discretization (stable)
- `div((nuEff*dev2(T(grad(U)))))` - stress tensor (linear)

**Reason**: Case focused on U and p only; no turbulence modeling (inviscid/laminar approximation)

### 6. **system/fvSolution** ✏️ MODIFIED
**Solvers**:
```cpp
p         → GAMG (multigrid)     [1e-6 tolerance, relTol 0.01]
pFinal    → GAMG (tighter)       [relTol 1e-4]
U         → PBiCG (iterative)    [1e-7 tolerance, relTol 0.01]
UFinal    → PBiCG (tighter)      [relTol 1e-4]
```

**Algorithm - PIMPLE**:
```cpp
nOuterCorrectors         3      // Fan pressure jump requires multiple iterations
nCorrectors              2      // Inner pressure-velocity corrections
nNonOrthogonalCorrectors 1      // Mesh correction
pRefPoint      (2.945 2.185 0.77)  // Office center reference
momentumPredictor        yes    // Enable momentum prediction step
```

**Removed**: All k and omega solver entries (not needed)

### 7. **system/controlDict** ✏️ MODIFIED
**Added Functions**:
```cpp
probes          // Monitor U and p at 5 downstream locations
residuals       // Track convergence of p and U
```

**Kept As-Is**:
- Solver: incompressibleFluid (transient)
- Duration: 10 seconds
- Time step: 0.05 s (CFL = u*dt/dx < 1 with 0.1m cells)
- adjustTimeStep: yes (auto-adjust for stability)
- maxCo: 0.7 (conservative Courant limit)

### 8. **Allrun** ✨ NEW (Updated)
**Execution sequence**:
1. blockMesh → Generate base mesh
2. topoSet → Create fan disc faceSet from searchableDisk
3. createPatch -overwrite → Convert faceZone to cyclic patch
4. checkMesh -allTopology → Verify topology
5. foamRun → Run incompressibleFluid solver

---

## Key Physical Implementation Details

### Fan Pressure Jump Model
The `fan` boundary condition implements:
$$p_{\text{downstream}} - p_{\text{upstream}} = f \cdot \frac{1}{2} \rho U^2$$

Where:
- **f** = dimensionless pressure rise coefficient (4.17 in this setup)
- **U** = velocity magnitude at fan plane
- **ρ** = fluid density (~1.2 kg/m³ for air)

**Calibration for your fan**:
- Measure actual Δp vs. flow rate from fan datasheet
- Compute f = 2*Δp / (ρ*U²)
- Update `f uniform 4.17;` in 0/p with actual value

### Cyclic Boundary Behavior
- Single patch spans entire fan disc
- **Upstream cells** (rear): Pressure dip drives suction → negative velocity (-X direction)
- **Downstream cells** (front): Pressure rise drives discharge → positive velocity (+X direction)
- PIMPLE algorithm iteratively couples pressure and velocity fields

### PIMPLE Algorithm for Fan Pressure Jump
```
For each outer iteration (3 total):
  ├─ Momentum prediction: Solve U with current p
  ├─ Pressure correction:
  │  └─ Solve Poisson equation for p'
  │     (incorporates fan pressure jump)
  ├─ Velocity correction: U ← U* + ∇p'/ρ
  └─ (Repeat 2x inner corrections)
```
More outer iterations (3 vs. standard 2) ensure fan pressure jump is properly captured.

---

## Simulation Execution Checklist

```bash
# Terminal 1: Run simulation
cd /home/bee17/CFD/airflow
chmod +x Allrun
./Allrun 2>&1 | tee log.simulation

# Terminal 2: Monitor progress (in parallel)
cd /home/bee17/CFD/airflow
tail -f log.simulation              # View solver output
tail -f postProcessing/residuals/0/residuals.dat  # Convergence

# After simulation completes:
paraFoam -builtin                   # Visualize results
```

**Expected Behavior**:
- t = 0-2s: Fan starts, jet develops from stagnant state
- t = 2-5s: Jet fully formed, recirculation zones develop
- t = 5-10s: Asymptotic approach to steady-state jet profile

---

## Customization Parameters

| Parameter | Location | Range | Notes |
|-----------|----------|-------|-------|
| Fan location | topoSetDict: origin | (x, y, z) | Change (1.5, 0.9, 0.9) to your fan position |
| Fan orientation | topoSetDict: normal | Unit vector | (1,0,0)=+X, (0,1,0)=+Y, (-1,0,0)=-X |
| Pressure rise | 0/p: f | 0.1–10.0 | Higher = stronger fan; start at 4.17, adjust per datasheet |
| Time step | controlDict: deltaT | 0.01–0.1 s | Smaller = more accurate but slower |
| Simulation duration | controlDict: endTime | 5–100 s | 10s typically enough for jet development |
| PIMPLE loops | fvSolution: nOuterCorrectors | 1–5 | More loops = better convergence but slower |

---

## Validation Metrics

**Monitor these outputs**:

1. **Residuals** (`postProcessing/residuals/0/residuals.dat`):
   - Should decrease monotonically
   - p and U residuals < 1e-4 by t=5s

2. **Probe Velocities** (`postProcessing/probes/0/U`):
   - Centerline (2.5, 0.9, 0.9): U_x ≈ 1.5–2.0 m/s at t=5s
   - Off-center points: U_x ≈ 0.5–1.0 m/s (jet spreading)
   - Asymptotic approach to steady profile

3. **Probe Pressures** (`postProcessing/probes/0/p`):
   - Pressure jump across fan ≈ 10 Pa initially
   - Decreases downstream as jet decelerates

4. **Mesh Quality** (`checkMesh -allTopology`):
   - No duplicate faces or hanging vertices
   - Non-orthogonality < 85° (good)
   - Aspect ratio < 1000 in bulk flow

---

## Troubleshooting Reference

| Issue | Probable Cause | Solution |
|-------|---|---|
| Fan BC not recognized | Cyclic patch not created | Verify `createPatch -overwrite` succeeded |
| Divergence/NaN | Time step too large | Reduce deltaT to 0.01 s |
| Solver stalls | Pressure jump f too high | Reduce f from 4.17 to 2.0 and rerun |
| Unrealistic jet shape | Mesh too coarse | Refine blockMeshDict, especially near fan |
| Memory/time issues | Mesh too fine globally | Coarsen far-field cells (away from fan) |

---

## Reference Parameters Summary

| Parameter | Value | Unit | Reason |
|-----------|-------|------|--------|
| **Fan diameter** | 0.4 | m | Given (0.4m stand fan) |
| **Fan radius** | 0.2 | m | Calculated from diameter |
| **Pressure rise** | 10 | Pa | Typical stand fan (~4.17 Pa/(m/s)² ) |
| **Inlet velocity** | 2 | m/s | Expected discharge velocity |
| **Air density** | 1.2 | kg/m³ | Standard room temperature (~23°C) |
| **Dynamic viscosity** | 1.81e-5 | Pa·s | Needed for wall effects (implicit in SIMPLE) |
| **Reynolds number** | ~55,000 | – | U*D/ν = 2*0.4/1.56e-5 (turbulent) |
| **Simulation duration** | 10 | s | Sufficient for jet development + relaxation |
| **Time step** | 0.05 | s | CFL ≈ 0.33 (safe, allows adjustment to 0.7) |

---

## Files Not Modified (Retained from Original)

- ✅ constant/polymesh/ (mesh topology)
- ✅ constant/transportProperties (fluid viscosity)
- ✅ system/blockMeshDict (geometry)
- ✅ 0/k, 0/omega, 0/nut (not used but present)

---

**Configuration prepared**: April 28, 2026  
**OpenFOAM version**: v2412 (dev)  
**Solver type**: incompressibleFluid (transient, PIMPLE)  
**Physics**: U and p only (no turbulence modeling)
