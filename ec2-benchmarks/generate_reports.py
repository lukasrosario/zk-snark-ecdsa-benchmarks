#!/usr/bin/env python3
import json
import plotly.graph_objects as go
import plotly.io as pio
import numpy as np
import sys
from pathlib import Path

def generate_summary_markdown(data, output_dir):
    """Generate a markdown summary of the performance data."""
    instance_type = data.get('instance_type', 'Unknown')
    cpu_cores = data.get('cpu_cores', 'N/A')
    memory_gb = data.get('memory_gb', 'N/A')
    timestamp = data.get('timestamp', 'N/A')
    proving_times = data.get('proving_times', {})
    gas_costs = data.get('gas_costs', {})
    
    md_content = f"""# ZK-SNARK ECDSA Benchmark Results

**Instance:** {instance_type}  
**CPU Cores:** {cpu_cores}  
**Memory:** {memory_gb}GB  
**Date:** {timestamp}

## Performance Summary
"""
    
    suites = sorted(list(set(list(proving_times.keys()) + list(gas_costs.keys()))))
    
    for suite in suites:
        md_content += f"\n### {suite}\n\n"
        if suite in proving_times:
            md_content += f"- **Proving Time:** {proving_times[suite]:.3f}s\n"
        if suite in gas_costs:
            md_content += f"- **Gas Cost:** {int(gas_costs[suite]):,} gas\n"
            
    summary_path = Path(output_dir) / 'performance_summary.md'
    with open(summary_path, 'w') as f:
        f.write(md_content)
    print(f"Generated markdown summary: {summary_path}")

def generate_plots(json_file_path):
    """Generate performance plots from JSON data file."""
    
    # Set up plotly for headless operation
    pio.defaults.mathjax = None
    
    # Load performance data
    try:
        with open(json_file_path) as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Error: JSON file {json_file_path} not found")
        return False
    except json.JSONDecodeError:
        print(f"Error: Invalid JSON in {json_file_path}")
        return False
    
    instance_type = data.get('instance_type', 'Unknown')
    proving_times = data.get('proving_times', {})
    verification_times = data.get('verification_times', {})
    gas_costs = data.get('gas_costs', {})
    raw_data = data.get('raw_data', {})
    
    # Get output directory from JSON file location
    output_dir = Path(json_file_path).parent
    
    # Generate the markdown summary
    generate_summary_markdown(data, output_dir)
    
    # Generate proving times plot with min, max, average
    if proving_times:
        suites = list(proving_times.keys())
        avg_times = list(proving_times.values())
        
        # Calculate min, max, and std dev from raw data
        min_times = []
        max_times = []
        std_devs = []
        
        for suite in suites:
            if suite in raw_data and 'proving_times' in raw_data[suite]:
                individual_times = raw_data[suite]['proving_times']
                min_times.append(min(individual_times))
                max_times.append(max(individual_times))
                if len(individual_times) > 1:
                    std_devs.append(np.std(individual_times, ddof=1))
                else:
                    std_devs.append(0)
            else:
                min_times.append(avg_times[len(min_times)])
                max_times.append(avg_times[len(max_times)])
                std_devs.append(0)
        
        # Create plotly figure
        fig = go.Figure()
        
        # Add average markers (large dots)
        fig.add_trace(go.Scatter(
            x=suites,
            y=avg_times,
            mode="markers",
            name="Average",
            marker=dict(color="blue", size=16),
            showlegend=True
        ))
        
        # Add vertical lines connecting min to max
        for i, suite in enumerate(suites):
            if min_times[i] != max_times[i]:
                fig.add_shape(
                    dict(type="line",
                         x0=suite,
                         x1=suite,
                         y0=min_times[i],
                         y1=max_times[i],
                         line=dict(color="blue", width=2))
                )
        
        # Add minimum and maximum markers with different colors
        fig.add_trace(go.Scatter(
            x=suites,
            y=min_times,
            mode="markers",
            name="Minimum",
            marker=dict(color="green", size=10),
            showlegend=True
        ))
        
        fig.add_trace(go.Scatter(
            x=suites,
            y=max_times,
            mode="markers",
            name="Maximum",
            marker=dict(color="red", size=10),
            showlegend=True
        ))
        
        # Add standard deviation information as text annotation
        std_text = "Standard Deviations:<br>" + "<br>".join([
            f"{suite}: σ={std_devs[i]:.3f}s" if std_devs[i] > 0 else f"{suite}: single measurement"
            for i, suite in enumerate(suites)
        ])
        
        fig.update_layout(
            title=f"ZK-SNARK Proving Times - {instance_type}",
            title_x=0.5,
            xaxis_title="ZK-SNARK Suite",
            yaxis_title="Proving Time (seconds)",
            width=1000,  # Increased width to make room for text
            height=500,
            showlegend=True,
            margin=dict(r=200),  # Add right margin for text
            annotations=[
                dict(
                    text=std_text,
                    xref="paper", yref="paper",
                    x=1.02, y=0.8,  # Position outside plot area
                    xanchor="left", yanchor="top",
                    showarrow=False,
                    font=dict(size=10),
                    bgcolor="rgba(255,255,255,0.8)",
                    bordercolor="black",
                    borderwidth=1
                )
            ]
        )
        
        fig.write_image(output_dir / 'proving_times.png')
        print("Generated proving_times.png")
    
    # Generate gas consumption plot with min, max, average
    if gas_costs:
        suites = list(gas_costs.keys())
        avg_costs = list(gas_costs.values())
        
        # Calculate min, max, and std dev from raw data
        min_costs = []
        max_costs = []
        std_devs = []
        
        for suite in suites:
            if suite in raw_data and 'gas_costs' in raw_data[suite]:
                individual_costs = raw_data[suite]['gas_costs']
                if individual_costs:
                    min_costs.append(min(individual_costs))
                    max_costs.append(max(individual_costs))
                    if len(individual_costs) > 1:
                        std_devs.append(np.std(individual_costs, ddof=1))
                    else:
                        std_devs.append(0)
                else:
                    # Handle case where gas_costs array is empty
                    avg_val = avg_costs[len(min_costs)]
                    min_costs.append(avg_val)
                    max_costs.append(avg_val)
                    std_devs.append(0)
            else:
                # Fallback if raw data is missing
                avg_val = avg_costs[len(min_costs)]
                min_costs.append(avg_val)
                max_costs.append(avg_val)
                std_devs.append(0)

        # Create plotly figure
        fig = go.Figure()
        
        # Add average markers (large dots)
        fig.add_trace(go.Scatter(
            x=suites,
            y=avg_costs,
            mode="markers",
            name="Average",
            marker=dict(color="blue", size=16),
            showlegend=True
        ))
        
        # Add vertical lines connecting min to max
        for i, suite in enumerate(suites):
            if min_costs[i] != max_costs[i]:
                fig.add_shape(
                    dict(type="line",
                         x0=suite,
                         x1=suite,
                         y0=min_costs[i],
                         y1=max_costs[i],
                         line=dict(color="blue", width=2))
                )
        
        # Add minimum and maximum markers with different colors
        fig.add_trace(go.Scatter(
            x=suites,
            y=min_costs,
            mode="markers",
            name="Minimum",
            marker=dict(color="green", size=10),
            showlegend=True
        ))
        
        fig.add_trace(go.Scatter(
            x=suites,
            y=max_costs,
            mode="markers",
            name="Maximum",
            marker=dict(color="red", size=10),
            showlegend=True
        ))
        
        # Add standard deviation information as text annotation
        std_text = "Standard Deviations:<br>" + "<br>".join([
            f"{suite}: σ={std_devs[i]:.0f}" if std_devs[i] > 0 else f"{suite}: deterministic"
            for i, suite in enumerate(suites)
        ])
        
        fig.update_layout(
            title=f"ZK-SNARK Gas Consumption - {instance_type}",
            title_x=0.5,
            xaxis_title="ZK-SNARK Suite",
            yaxis_title="Gas Consumption",
            width=1000,  # Increased width to make room for text
            height=500,
            showlegend=True,
            margin=dict(r=200),  # Add right margin for text
            annotations=[
                dict(
                    text=std_text,
                    xref="paper", yref="paper",
                    x=1.02, y=0.8,  # Position outside plot area
                    xanchor="left", yanchor="top",
                    showarrow=False,
                    font=dict(size=10),
                    bgcolor="rgba(255,255,255,0.8)",
                    bordercolor="black",
                    borderwidth=1
                )
            ]
        )
        
        fig.write_image(output_dir / 'gas_consumption.png')
        print("Generated gas_consumption.png")
    
    print("Plot generation completed!")
    return True

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 generate_plots.py <performance_data.json>")
        sys.exit(1)
    
    json_file = sys.argv[1]
    success = generate_plots(json_file)
    sys.exit(0 if success else 1) 