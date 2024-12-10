`timescale 1ns / 1ps

// ============================================
// Macro Definitions
// ============================================

// Macro to calculate the ceiling of log2(x)
// This determines the number of bits required to represent 'x' in binary

`define CLOG2(x) \
    ((x <= 1) ? 0 : \
     (x <= 2) ? 1 : \
     (x <= 4) ? 2 : \
     (x <= 8) ? 3 : \
     (x <= 16) ? 4 : \
     (x <= 32) ? 5 : \
     (x <= 64) ? 6 : \
     (x <= 128) ? 7 : \
     (x <= 256) ? 8 : \
     (x <= 512) ? 9 : \
     (x <= 1024) ? 10 : 11)

// ============================================
// 1. DecisionTreeNode Module
// ============================================

/*
 * Module: DecisionTreeNode
 * ------------------------
 * Represents a single node in the decision tree.
 *
 * Parameters:
 * - THRESHOLD: Threshold value for decision-making.
 * - FEATURE_INDEX: Index of the feature to evaluate.
 * - NUM_FEATURES: Total number of features.
 * - IS_LEAF: Indicates whether the node is a leaf (1) or internal (0).
 *
 * Inputs:
 * - feature_values_packed: Packed array of feature values.
 * - clk: Clock signal.
 * - rst: Reset signal.
 *
 * Outputs:
 * - go_left: Signal to traverse to the left child.
 * - go_right: Signal to traverse to the right child.
 * - classification: Classification result if the node is a leaf.
 * - is_leaf: Indicates if the node is a leaf.
 */

module DecisionTreeNode #(
    parameter THRESHOLD = 0,
    parameter FEATURE_INDEX = 0,
    parameter NUM_FEATURES = 20000,
    parameter IS_LEAF = 0
) (
    input [NUM_FEATURES*8-1:0] feature_values_packed, // Packed feature array (8 bits per feature)
    input clk, rst,                                   // Clock and reset signals
    output reg go_left, go_right,                     // Control signals for traversal
    output reg classification,                        // Classification result (if leaf)
    output reg is_leaf                                // Indicates if the node is a leaf
);
    
    // ========================================
    // Unpack Feature Values
    // ========================================

    wire [7:0] feature_values [0:NUM_FEATURES-1]; // Array to hold individual feature values
    
    genvar i;
    generate
        for (i = 0; i < NUM_FEATURES; i = i + 1) begin : unpack_features
            assign feature_values[i] = feature_values_packed[i*8 +: 8];
        end
    endgenerate

    // ========================================
    // Node Logic
    // ========================================
    
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset all outputs
            go_left <= 0;
            go_right <= 0;
            classification <= 0;
            is_leaf <= 0;
        end else begin
            if (IS_LEAF) begin
                // Leaf Node: Provide classification result
                is_leaf <= 1;
                classification <= (feature_values[FEATURE_INDEX] < THRESHOLD) ? 1 : 0;
                go_left <= 0;
                go_right <= 0;
            end else begin
                // Internal Node: Decide traversal direction based on threshold
                is_leaf <= 0;
                if (feature_values[FEATURE_INDEX] < THRESHOLD) begin
                    go_left <= 1;
                    go_right <= 0;
                end else begin
                    go_left <= 0;
                    go_right <= 1;
                end
            end
        end
    end
endmodule

// ============================================
// 2. TreeController Module
// ============================================

/*
 * Module: TreeController
 * ----------------------
 * Controls the traversal of the decision tree based on traversal signals from nodes.
 *
 * Parameters:
 * - MAX_DEPTH: Maximum depth of the decision tree.
 *
 * Inputs:
 * - clk: Clock signal.
 * - rst: Reset signal.
 * - go_left: Signal to traverse to the left child.
 * - go_right: Signal to traverse to the right child.
 * - is_leaf: Indicates if the current node is a leaf.
 *
 * Outputs:
 * - traversal_done: Indicates that traversal has completed.
 * - final_node_index: Index of the leaf node where traversal ended.
 */

module TreeController #(
    parameter MAX_DEPTH = 10
) (
    input clk, rst,                                // Clock and reset signals
    input go_left, go_right,                       // Traversal signals from current node
    input is_leaf,                                 // Indicates if current node is a leaf
    output reg traversal_done,                     // Signal indicating traversal completion
    output reg [`CLOG2((2**MAX_DEPTH)-1)-1:0] final_node_index // Leaf node index
);
    
    // Current node tracker
    reg [`CLOG2((2**MAX_DEPTH)-1)-1:0] current_node;

    // Traversal Logic
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Initialize traversal at root
            current_node <= 0;
            traversal_done <= 0;
            final_node_index <= 0;
        end else begin
            if (!traversal_done) begin
                if (is_leaf) begin
                    // Reached a leaf node; end traversal
                    traversal_done <= 1;
                    final_node_index <= current_node;
                end else if (go_left) begin
                    // Move to left child: node index = current_node * 2 + 1
                    current_node <= (current_node << 1) + 1;
                end else if (go_right) begin
                    // Move to right child: node index = current_node * 2 + 2
                    current_node <= (current_node << 1) + 2;
                end
            end
        end
    end
endmodule

// ============================================
// 3. DecisionTree Top-Level Module
// ============================================

/*
 * Module: DecisionTree
 * ---------------------
 * Top-level module representing the entire decision tree.
 *
 * Parameters:
 * - DEPTH: Depth of the decision tree.
 * - NUM_FEATURES: Number of features in the dataset (must be >= (2^DEPTH - 1)).
 *
 * Inputs:
 * - feature_values_packed: Packed array of feature values.
 * - clk: Clock signal.
 * - rst: Reset signal.
 *
 * Outputs:
 * - classification_result: Final classification result after traversal.
 */

module DecisionTree #(
    parameter DEPTH = 10,
    parameter NUM_FEATURES = 20000 // Must be >= (2^DEPTH - 1)
) (
    input [NUM_FEATURES*8-1:0] feature_values_packed, // Packed feature array (8 bits per feature)
    input clk, rst,                                   // Clock and reset signals
    output reg classification_result                  // Final classification result
);
    
    // Total number of nodes in a complete binary tree of given depth

    localparam NUM_NODES = (2 ** DEPTH) - 1;

    // Wires to hold signals from all nodes

    wire [NUM_NODES-1:0] go_left, go_right, is_leaf;
    wire [NUM_NODES-1:0] classifications;

    // Instantiate DecisionTreeNode modules for each node in the tree

    genvar i;
    generate
        for (i = 0; i < NUM_NODES; i = i + 1) begin : node_instantiation

            // Determine if the current node is a leaf

            localparam LEAF_START = (2**(DEPTH-1)) - 1;
            localparam IS_LEAF = (i >= LEAF_START) ? 1 : 0;

            // Instantiate a DecisionTreeNode with appropriate parameters

            DecisionTreeNode #(
                .THRESHOLD(8'd10 + i),       // Example threshold (can be customized)
                .FEATURE_INDEX(i),           // Unique feature index per node
                .NUM_FEATURES(NUM_FEATURES),
                .IS_LEAF(IS_LEAF)
            ) node (
                .feature_values_packed(feature_values_packed),
                .clk(clk),
                .rst(rst),
                .go_left(go_left[i]),
                .go_right(go_right[i]),
                .classification(classifications[i]),
                .is_leaf(is_leaf[i])
            );
        end
    endgenerate

    // Signals from the TreeController

    wire traversal_done;
    wire [`CLOG2((2**DEPTH)-1)-1:0] final_node_index;

    // Instantiate the TreeController to manage traversal

    TreeController #(
        .MAX_DEPTH(DEPTH)
    ) controller (
        .clk(clk),
        .rst(rst),
        .go_left(go_left[0]),   // Root node's go_left signal
        .go_right(go_right[0]), // Root node's go_right signal
        .is_leaf(is_leaf[0]),    // Root node's is_leaf signal
        .traversal_done(traversal_done),
        .final_node_index(final_node_index)
    );

    // ========================================
    // Final Classification Result
    // ========================================

    always @(posedge clk or posedge rst) begin
        if (rst)
            classification_result <= 0;
        else if (traversal_done)
            classification_result <= classifications[final_node_index];
    end
endmodule

// ============================================
// 4. DecisionTree_tb Testbench
// ============================================

`timescale 1ns / 1ps

/*
 * Module: DecisionTree_tb
 * ------------------------
 * Testbench for the DecisionTree module.
 *
 * Parameters:
 * - DEPTH: Depth of the decision tree for testing.
 * - NUM_FEATURES: Number of features for testing.
 *
 * Functionality:
 * - Reads test cases from a CSV file.
 * - Applies each test case to the DecisionTree module.
 * - Compares the module's output with the expected result.
 * - Reports statistics on classification accuracy.
 */

module DecisionTree_tb;

    // Testbench Parameters

    parameter DEPTH = 10;
    parameter NUM_FEATURES = 20000;

    // Testbench Signals

    reg clk, rst;
    reg [7:0] feature_values [0:NUM_FEATURES-1]; // Array of feature values (8 bits each)
    wire classification_result;

    // Testbench Statistics

    integer correct_count = 0;
    integer total_count = 0;
    integer misclassified_count = 0; // Number of incorrect classifications
    integer file, status;             // File handling variables
    reg [7:0] expected_result;        // Expected classification result
    reg [1023:0] dummy_line;          // Temporary storage for header line

    // Packed feature values vector

    reg [NUM_FEATURES*8-1:0] feature_values_packed;

    // ========================================
    // Pack Feature Values
    // ========================================

    // Continuously pack the feature_values array into a single vector

    always @(*) begin
        feature_values_packed = 0;
        for (integer i = 0; i < NUM_FEATURES; i = i + 1) begin
            feature_values_packed[i*8 +: 8] = feature_values[i];
        end
    end

    // ========================================
    // Instantiate the DecisionTree Module
    // ========================================

    DecisionTree #(
        .DEPTH(DEPTH),
        .NUM_FEATURES(NUM_FEATURES)
    ) tree (
        .feature_values_packed(feature_values_packed), // Pass the packed feature vector
        .clk(clk),
        .rst(rst),
        .classification_result(classification_result)
    );

    // ========================================
    // Clock Generation
    // ========================================

    initial begin
        clk = 0;
        forever #5 clk = ~clk; // Toggle clock every 5ns (100MHz)
    end

    // ========================================
    // Reset Logic
    // ========================================

    initial begin
        rst = 1;          // Assert reset
        #15 rst = 0;      // De-assert reset after 15ns
    end

    // ========================================
    // Test Case Processing
    // ========================================

    initial begin
        // Open the test cases CSV file
        file = $fopen("test_cases.csv", "r");
        if (file == 0) begin
            $display("Error: Failed to open test_cases.csv");
            $finish;
        end

        // Read and discard the header line
        status = $fgets(dummy_line, file);
        if (status == 0) begin
            $display("Error: Failed to read header from test_cases.csv");
            $finish;
        end

        // Process each test case until end of file
        while (!$feof(file)) begin
            // Read feature values
            for (integer i = 0; i < NUM_FEATURES; i = i + 1) begin
                status = $fscanf(file, "%d,", feature_values[i]);
                if (status != 1) begin
                    $display("Error: Malformed line in test_cases.csv");
                    $finish;
                end
            end

            // Read the expected classification result
            status = $fscanf(file, "%d\n", expected_result);
            if (status != 1) begin
                $display("Error: Missing expected result in test_cases.csv");
                $finish;
            end

            // Wait for a couple of clock cycles to allow the DecisionTree to process
            @(posedge clk);
            @(posedge clk);

            // Update test statistics
            total_count = total_count + 1;

            if (classification_result === expected_result) begin
                correct_count = correct_count + 1;
            end else begin
                misclassified_count = misclassified_count + 1;
                // Display misclassified test case details
                $display("Misclassified Test Case #%d:", total_count);
                for (integer i = 0; i < NUM_FEATURES; i = i + 1)
                    $display("  Feature[%0d]: %0d", i, feature_values[i]);
                $display("  Expected: %0d, Got: %0d", expected_result, classification_result);
            end
        end

        // Close the test cases file
        $fclose(file);

        // Display final test statistics
        $display("=======================================");
        $display("          TESTBENCH REPORT             ");
        $display("=======================================");
        $display("Total Test Cases        : %0d", total_count);
        $display("Correct Classifications : %0d", correct_count);
        $display("Misclassified Cases     : %0d", misclassified_count);
        if (total_count > 0)
            $display("Accuracy                : %.2f%%", (correct_count * 100.0) / total_count);
        else
            $display("No test cases were processed.");
        $display("=======================================");
        $finish;
    end
endmodule
