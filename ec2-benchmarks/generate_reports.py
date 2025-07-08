#!/usr/bin/env python3
import json
import matplotlib.pyplot as plt
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
    
    # Set up matplotlib for headless operation
    plt.switch_backend('Agg')
    
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
        
        # Create grouped bar chart
        x = np.arange(len(suites))
        width = 0.25
        
        plt.figure(figsize=(12, 7))
        
        bars1 = plt.bar(x - width, min_times, width, label='Minimum', alpha=0.8, color='#2ca02c')
        bars2 = plt.bar(x, avg_times, width, label='Average', alpha=0.8, color='#1f77b4')  
        bars3 = plt.bar(x + width, max_times, width, label='Maximum', alpha=0.8, color='#d62728')
        
        plt.xlabel('ZK-SNARK Suite')
        plt.ylabel('Proving Time (seconds)')
        plt.title(f'ZK-SNARK Proving Times - {instance_type}')
        plt.xticks(x, suites, rotation=45)
        plt.grid(True, alpha=0.3)
        
        # Add std dev info to legend
        legend_labels = []
        for i, suite in enumerate(suites):
            if std_devs[i] > 0:
                legend_labels.append(f'{suite}: σ={std_devs[i]:.3f}s')
            else:
                legend_labels.append(f'{suite}: single measurement')
        
        # Create custom legend and place it outside the plot
        plt.legend(title='Statistics', bbox_to_anchor=(1.05, 1), loc='upper left', borderaxespad=0.)
        
        # Add std dev text outside the plot
        std_text = "Standard Deviations:\n" + "\n".join(legend_labels)
        plt.text(1.05, 0.8, std_text, transform=plt.gca().transAxes, 
                 verticalalignment='top', horizontalalignment='left',
                 bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8),
                 fontsize=9)
        
        # Add value labels on bars
        def add_value_labels(bars, values):
            for bar, value in zip(bars, values):
                plt.text(bar.get_x() + bar.get_width()/2, bar.get_height() + max(max_times)*0.01,
                        f'{value:.3f}s', ha='center', va='bottom', fontsize=8, rotation=0)
        
        add_value_labels(bars1, min_times)
        add_value_labels(bars2, avg_times)
        add_value_labels(bars3, max_times)
        
        plt.tight_layout()
        plt.savefig(output_dir / 'proving_times.png', dpi=300, bbox_inches='tight')
        plt.close()
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

        # Create grouped bar chart
        x = np.arange(len(suites))
        width = 0.25
        
        plt.figure(figsize=(12, 7))
        
        bars1 = plt.bar(x - width, min_costs, width, label='Minimum', alpha=0.8, color='#2ca02c')
        bars2 = plt.bar(x, avg_costs, width, label='Average', alpha=0.8, color='#1f77b4')  
        bars3 = plt.bar(x + width, max_costs, width, label='Maximum', alpha=0.8, color='#d62728')
        
        plt.xlabel('ZK-SNARK Suite')
        plt.ylabel('Gas Consumption')
        plt.title(f'ZK-SNARK Gas Consumption - {instance_type}')
        plt.xticks(x, suites, rotation=45)
        plt.grid(True, alpha=0.3)
        plt.ticklabel_format(style='scientific', axis='y', scilimits=(0,0))
        
        # Add std dev info to legend
        legend_labels = []
        for i, suite in enumerate(suites):
            if std_devs[i] > 0:
                legend_labels.append(f'{suite}: σ={std_devs[i]:.2f}')
            else:
                legend_labels.append(f'{suite}: deterministic')
        
        # Create custom legend and place it outside the plot
        plt.legend(title='Statistics', bbox_to_anchor=(1.05, 1), loc='upper left', borderaxespad=0.)
        
        # Add std dev text outside the plot
        std_text = "Standard Deviations:\n" + "\n".join(legend_labels)
        plt.text(1.05, 0.8, std_text, transform=plt.gca().transAxes, 
                 verticalalignment='top', horizontalalignment='left',
                 bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8),
                 fontsize=9)
        
        # Add value labels on bars
        def add_value_labels(bars, values):
            for bar, value in zip(bars, values):
                plt.text(bar.get_x() + bar.get_width()/2, bar.get_height() + max(max_costs)*0.02,
                        f'{value:.0f}', ha='center', va='bottom', fontsize=8, rotation=0)
        
        add_value_labels(bars1, min_costs)
        add_value_labels(bars2, avg_costs)
        add_value_labels(bars3, max_costs)
        
        plt.tight_layout()
        plt.savefig(output_dir / 'gas_consumption.png', dpi=300, bbox_inches='tight')
        plt.close()
        print("Generated gas_consumption.png")
    
    print("Plot generation completed!")
    return True
    """Generate performance plots from JSON data file."""
    
    # Set up matplotlib for headless operation
    plt.switch_backend('Agg')
    
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
        
        # Create grouped bar chart
        x = np.arange(len(suites))
        width = 0.25
        
        plt.figure(figsize=(12, 7))
        
        bars1 = plt.bar(x - width, min_times, width, label='Minimum', alpha=0.8, color='#2ca02c')
        bars2 = plt.bar(x, avg_times, width, label='Average', alpha=0.8, color='#1f77b4')  
        bars3 = plt.bar(x + width, max_times, width, label='Maximum', alpha=0.8, color='#d62728')
        
        plt.xlabel('ZK-SNARK Suite')
        plt.ylabel('Proving Time (seconds)')
        plt.title(f'ZK-SNARK Proving Times - {instance_type}')
        plt.xticks(x, suites, rotation=45)
        plt.grid(True, alpha=0.3)
        
        # Add std dev info to legend
        legend_labels = []
        for i, suite in enumerate(suites):
            if std_devs[i] > 0:
                legend_labels.append(f'{suite}: σ={std_devs[i]:.3f}s')
            else:
                legend_labels.append(f'{suite}: single measurement')
        
        # Create custom legend and place it outside the plot
        plt.legend(title='Statistics', bbox_to_anchor=(1.05, 1), loc='upper left', borderaxespad=0.)
        
        # Add std dev text outside the plot
        std_text = "Standard Deviations:\n" + "\n".join(legend_labels)
        plt.text(1.05, 0.8, std_text, transform=plt.gca().transAxes, 
                 verticalalignment='top', horizontalalignment='left',
                 bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8),
                 fontsize=9)
        
        # Add value labels on bars
        def add_value_labels(bars, values):
            for bar, value in zip(bars, values):
                plt.text(bar.get_x() + bar.get_width()/2, bar.get_height() + max(max_times)*0.01,
                        f'{value:.3f}s', ha='center', va='bottom', fontsize=8, rotation=0)
        
        add_value_labels(bars1, min_times)
        add_value_labels(bars2, avg_times)
        add_value_labels(bars3, max_times)
        
        plt.tight_layout()
        plt.savefig(output_dir / 'proving_times.png', dpi=300, bbox_inches='tight')
        plt.close()
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

        # Create grouped bar chart
        x = np.arange(len(suites))
        width = 0.25
        
        plt.figure(figsize=(12, 7))
        
        bars1 = plt.bar(x - width, min_costs, width, label='Minimum', alpha=0.8, color='#2ca02c')
        bars2 = plt.bar(x, avg_costs, width, label='Average', alpha=0.8, color='#1f77b4')  
        bars3 = plt.bar(x + width, max_costs, width, label='Maximum', alpha=0.8, color='#d62728')
        
        plt.xlabel('ZK-SNARK Suite')
        plt.ylabel('Gas Consumption')
        plt.title(f'ZK-SNARK Gas Consumption - {instance_type}')
        plt.xticks(x, suites, rotation=45)
        plt.grid(True, alpha=0.3)
        plt.ticklabel_format(style='scientific', axis='y', scilimits=(0,0))
        
        # Add std dev info to legend
        legend_labels = []
        for i, suite in enumerate(suites):
            if std_devs[i] > 0:
                legend_labels.append(f'{suite}: σ={std_devs[i]:.2f}')
            else:
                legend_labels.append(f'{suite}: deterministic')
        
        # Create custom legend and place it outside the plot
        plt.legend(title='Statistics', bbox_to_anchor=(1.05, 1), loc='upper left', borderaxespad=0.)
        
        # Add std dev text outside the plot
        std_text = "Standard Deviations:\n" + "\n".join(legend_labels)
        plt.text(1.05, 0.8, std_text, transform=plt.gca().transAxes, 
                 verticalalignment='top', horizontalalignment='left',
                 bbox=dict(boxstyle='round', facecolor='wheat', alpha=0.8),
                 fontsize=9)
        
        # Add value labels on bars
        def add_value_labels(bars, values):
            for bar, value in zip(bars, values):
                plt.text(bar.get_x() + bar.get_width()/2, bar.get_height() + max(max_costs)*0.02,
                        f'{value:.0f}', ha='center', va='bottom', fontsize=8, rotation=0)
        
        add_value_labels(bars1, min_costs)
        add_value_labels(bars2, avg_costs)
        add_value_labels(bars3, max_costs)
        
        plt.tight_layout()
        plt.savefig(output_dir / 'gas_consumption.png', dpi=300, bbox_inches='tight')
        plt.close()
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