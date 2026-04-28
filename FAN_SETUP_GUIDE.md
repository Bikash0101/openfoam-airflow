# OpenFOAM Stand Fan Simulation - Setup & Execution Guide

## Overview
This configuration adapts the roomResidenceTime case structure for simulating a **0.4m diameter stand fan** in a closed office with partition walls. The setup focuses on **U (velocity)** and **p (pressure)** fields only, using the incompressibleFluid solver with fan pressure jump boundary condition.

## Key Configuration Changes

### 1. Geometry & Mesh (topoSetDict)

**Fan Specification:**
- **Type**: searchableDisk (circular disc)
- **Location**: (1.5, 0.9, 0.9) m - center of fan in office space
- **Diameter**: 0.4 m (Radius: 0.2 m)
- **Orientation**: Normal vector = (1, 0, 0) - discharge along +X axis
- **Purpose**: Defines the fan as a thin discontinuity surface for pressure jump

**Mesh Command Sequence:**
```bash
# Step 1: Generate base mesh
blockMesh

# Step 2: Create fan disc faceSet from searchableDisk
topoSet

# Step 3: Convert faceZone to cyclic patch
createPatch -overwrite
```

### 2. Boundary Conditions

#### Pressure Field (0/p)
```cpp
fan
{
    type            fan;
    patchType       cyclic;
    
    // Pressure rise parameter (dimensionless)
    // f = ΔP / (0.5 * ρ * U²)
    // For ΔP = 10 Pa, U = 2 m/s, ρ = 1.2 kg/m³:
    // f = 10 / (0.5 * 1.2 * 4) = 4.17
    f               uniform 4.17;
    
    // Required for v2412 unified solver
    phi             phi;            // Flux field
    rho             rho;            // Density (if incompressible, ~1.0)
}
```

**Pressure Jump Interpretation:**
- The fan BC enforces: $p_{\text{downstream}} - p_{\text{upstream}} = f \cdot 0.5 \cdot \rho \cdot U^2$
- This mimics a real fan performance curve
- Can be made velocity-dependent using `tableFile` instead of `uniform`

#### Velocity Field (0/U)
```cpp
fan
{
    type            cyclic;
}
```

**Cyclic Boundary:**
- Allows fluid to pass through both sides of the disc
- **Inlet side** (rear): Suction boundary (~0 velocity or slight negative)
- **Outlet side** (front): Discharge boundary (determined by pressure solver)
- The PIMPLE algorithm couples U and p to achieve consistency

#### Wall Boundaries
- **floor, ceiling, walls, partition**: `type noSlip` for U and `zeroGradient` for p
- Ensures no-penetration and viscous wall effects

### 3. Numerical Schemes (fvSchemes)

**Simplified for U and p only:**
```cpp
divSchemes
{
    div(phi,U)      Gauss upwind;           // 2nd-order momentum convection
    div((nuEff*dev2(T(grad(U))))) Gauss linear;  // Stress tensor
}
```

**Note**: Removed `div(phi,k)` and `div(phi,omega)` since turbulence is not modeled.

### 4. Solver Algorithm (fvSolution)

**PIMPLE Configuration:**
```cpp
PIMPLE
{
    nOuterCorrectors 3;              // 3 outer loops for fan pressure jump convergence
    nCorrectors      2;              // 2 inner pressure-velocity corrections
    nNonOrthogonalCorrectors 1;      // 1 iteration for mesh correction
    pRefPoint (2.945 2.185 0.77);    // Reference point (office center)
    pRefValue 0;                     // Reference pressure
    momentumPredictor yes;           // Use momentum prediction step
}
```

**Why PIMPLE?**
- PIMPLE = PISO + Outer loop iterations
- PISO alone (1 outer loop) may not capture fan pressure jump accurately
- 3 outer loops allow the pressure field to equilibrate across the fan disc

**Solver Selection:**
- **Pressure (p)**: GAMG (Geometric Algebraic MultiGrid) - efficient for pressure systems
- **Velocity (U)**: PBiCG (Preconditioned BiConjugate Gradient) - handles non-symmetric momentum matrix

### 5. Time Stepping (controlDict)

```cpp
deltaT          0.05;           // 50ms time step
adjustTimeStep  yes;
maxCo           0.7;            // Max Courant number = 0.7
endTime         10;             // Simulate 10 seconds
writeInterval   0.1;            // Write output every 0.1 seconds
```

**CFL Number:**
- $\text{Co} = \frac{u \cdot \Delta t}{\Delta x} < 1$ (stability requirement)
- With fan jet at ~2 m/s and cell size ~0.1m: $\text{dt} < 0.05$s ✓

### 6. Monitoring (functions in controlDict)

Two monitoring functions are included:

**Probes Function:**
Samples U and p at 5 locations along the fan jet:
- (2.5, 0.9, 0.9) - 1.0 m downstream (jet centerline)
- (2.5, 1.1, 0.9) - 0.2 m off-center
- (2.5, 0.7, 0.9) - 0.2 m off-center
- (3.0, 0.9, 0.9) - 1.5 m downstream
- (4.0, 0.9, 0.9) - 2.5 m downstream

**Residuals Function:**
Tracks convergence of p and U solvers per time step.

## Execution Steps

### Pre-Simulation Setup

**1. Run topoSet to create fan surface:**
```bash
cd /home/bee17/CFD/airflow
topoSet
```

**Expected output:**
- Creates `postProcessing/fanFaceSet/` with the disc faces
- Creates `postProcessing/fanZone/` as a faceZone

**2. Create the cyclic patch:**
```bash
createPatch -overwrite
```

**Expected output:**
- Adds `fan` patch to `constant/polyMesh/boundary`
- Converts `fanZone` faceZone into boundary patch

**3. Verify patch creation:**
```bash
checkMesh -allTopology
```

Should show:
- Fan patch defined as cyclic
- No duplicate faces or invalid topology

### Run Simulation

**Start the transient simulation:**
```bash
foamRun 2>&1 | tee log.foamRun
```

**Monitor progress:**
```bash
tail -f log.foamRun              # View live output
tail -f postProcessing/residuals/0/residuals.dat  # View convergence
```

### Post-Processing

**1. Check jet velocity development:**
```bash
cat postProcessing/probes/0/U
```

Should show:
- Time evolution of U at each probe point
- Expected: U increases from 0 to ~1.5-2.0 m/s at centerline over first 2-3 seconds
- Asymptotic approach to steady jet profile

**2. View pressure field:**
```bash
paraFoam -builtin
```

Navigate to:
- Time step (e.g., t = 5s) when flow is fully developed
- Scalar field: p
- Look for pressure jump across fan disc region
- Pressure contours in wake/recirculation zones

**3. Velocity magnitude field:**
```bash
# In ParaView:
# 1. Load latest time step
# 2. Display: Velocity -> Magnitude
# 3. Apply
# 4. Use clipping plane (X = 1.5) to visualize disc location
```

Expected patterns:
- High velocity jet emanating from fan (+X direction)
- Suction zone immediately behind fan disc
- Jet spreading as it progresses downstream
- Recirculation zones near office walls and partitions

## Customization Guide

### Adjusting Fan Pressure Jump

If fan produces too much/little flow:

**In 0/p:**
```cpp
f  uniform 4.17;  // Increase value for stronger suction/discharge
```

**Alternative:** Use actual fan curve data
```cpp
f  table ((0 0.001)(0.1 4.0)(0.2 3.8)(0.3 3.2));  // (flow_rate, f_coefficient)
```

### Changing Fan Location or Orientation

**In system/topoSetDict:**
```cpp
origin  (1.5 0.9 0.9);     // Change fan center
normal  (1 0 0);            // Change orientation: (1 0 0) = +X, (0 1 0) = +Y, etc.
radius  0.2;                // Keep at 0.2 (0.4m diameter)
```

Then re-run: `topoSet` and `createPatch -overwrite`

### Monitoring Additional Quantities

**Add surface sample:**
```cpp
// Add to functions in controlDict:
surfaces
{
    type            surfaces;
    libs            ("libsampling.so");
    writeControl    writeTime;
    
    surfaceFormat   vtp;
    fields          (U p);
    
    surfaces
    (
        fan_plane
        {
            type            plane;
            basePoint       (1.5 0.9 0.9);
            normalVector    (1 0 0);
            offsets         (-0.2 0 0.2 0.4);  // Sample at ±0.2m from fan
        }
    );
}
```

### Reducing Computational Cost

If simulation is too slow:

1. **Coarsen mesh** near far-field (away from fan)
   - Edit blockMeshDict: reduce cells in remote zones
   - Re-run `blockMesh`

2. **Increase time step** (trade accuracy for speed)
   ```cpp
   deltaT  0.1;      // From 0.05
   maxCo   1.0;       // From 0.7 (less stable but faster)
   ```

3. **Reduce simulation time**
   ```cpp
   endTime  5;        // From 10 (fewer seconds to simulate)
   ```

4. **Relax convergence criteria in fvSolution**
   ```cpp
   tolerance  1e-5;   // From 1e-6 (more iterations allowed)
   ```

## Physical Validation Checklist

☐ Fan produces roughly uniform jet velocity (U ≈ 2 m/s) at discharge  
☐ Jet spreads and velocity decreases downstream (expected for turbulent jet)  
☐ Pressure jump across fan disc visible (~5-10 Pa)  
☐ Suction zone behind fan (pressure dip)  
☐ No negative pressures in domain (incompressible flow assumption)  
☐ Residuals decay monotonically (no oscillations)  
☐ Mass balance: $Q_{\text{inlet}} = Q_{\text{outlet}}$ (conservation)  

## Troubleshooting

### Issue: Divergence or Blow-up

**Cause**: Time step too large or pressure jump too high
- **Fix**: Reduce `deltaT` to 0.01s or `f` to 2.0

**Cause**: Non-orthogonal mesh near fan
- **Fix**: Check mesh quality with `checkMesh -allTopology`

### Issue: Fan BC not recognized

**Cause**: Cyclic patch not created properly
- **Fix**: Verify `createPatchDict` ran successfully
  ```bash
  grep -i "fan" constant/polyMesh/boundary
  ```

### Issue: Unrealistic jet decay

**Cause**: Numerical diffusion (upwind discretization is dissipative)
- **Fix**: Can use `bounded Gauss linear` instead of `upwind` (if stable)

## References

- **OpenFOAM v2412 Solver**: incompressibleFluid with PIMPLE
- **Fan BC**: Implementation in `$FOAM_SRC/finiteVolume/fields/fvPatchFields/derived/fan/`
- **Pressure Jump Formula**: $\Delta p = f \cdot \frac{1}{2} \rho U^2$ (momentum source interpretation)

---

**Configuration created**: April 28, 2026  
**OpenFOAM Version**: v2412 (dev)  
**Solver**: incompressibleFluid (U, p only - no turbulence)
