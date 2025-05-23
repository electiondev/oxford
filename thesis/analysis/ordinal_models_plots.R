# This script generates plots for the ordinal regression models
# using the ggpredict function from the ggeffects package instead of svolyr

# Load required scripts to run the analysis in this file
source("../analysis/data.R")
source("../analysis/data_cleaning.R")
source("../analysis/survey_design.R")
source("../analysis/ordinal_models.R")

# 1. Fit an ordinal regression model (polr) with interactions and covariates
fit_polr_model <- function(data, outcome, treatment, moderators = NULL, covariates = NULL) {
    rhs <- treatment
    if (!is.null(covariates)) rhs <- c(rhs, covariates)
    if (!is.null(moderators)) {
        interaction_terms <- paste0(treatment, " * ", moderators)
        rhs <- c(rhs, interaction_terms)
    }
    formula_str <- paste(outcome, "~", paste(rhs, collapse = " + "))
    polr(
        formula = as.formula(formula_str),
        data = data,
        method = "logistic",
        Hess = TRUE
    )
}

# 2. Generate predicted probabilities for specific levels/subgroups
#    - levels_list: a named list like list("LowEdu" = c("ai_treatment", "education_recode[Low]"), ...)
get_preds_for_subgroups <- function(model, levels_list, collapse_levels, shape_labels = c("Control", "Treatment")) {
    collapse_preds <- function(term_vec, subgroup_label) {
        preds <- ggpredict(model, terms = term_vec) %>%
            filter(response.level %in% collapse_levels) %>%
            group_by(x) %>%
            summarise(
                predicted = sum(predicted),
                conf.low = sum(predicted) - sqrt(sum((predicted - conf.low)^2)),
                conf.high = sum(conf.high),
                .groups = "drop"
            ) %>%
            mutate(
                treatment = ifelse(x == 0, shape_labels[1], shape_labels[2]),
                mod_group = subgroup_label
            )
        preds
    }
    res <- bind_rows(
        lapply(names(levels_list), function(nm) collapse_preds(levels_list[[nm]], nm))
    )
    return(res)
}

# 3. Get predictions for 'overall' (no moderator)
get_overall_preds <- function(model, treatment, collapse_levels, shape_labels = c("Control", "Treatment")) {
    ggpredict(model, terms = treatment) %>%
        filter(response.level %in% collapse_levels) %>%
        group_by(x) %>%
        summarise(
            predicted = sum(predicted),
            conf.low = sum(conf.low),
            conf.high = sum(conf.high),
            .groups = "drop"
        ) %>%
        mutate(
            treatment = ifelse(x == 0, shape_labels[1], shape_labels[2]),
            mod_group = "Overall"
        )
}

# 4. Main plotting function
generate_ordinal_preds_plot <- function(
    data,
    outcome,
    treatment,
    moderators = NULL,
    covariates = NULL,
    moderator_terms = list(), # e.g., list(LowEdu = c("ai_treatment", "education_recode[Low]"))
    collapse_levels, # levels of outcome to collapse (e.g., disagreement, low trust, etc.)
    moderator_labels = NULL, # (optional) labels for plot x-axis
    plot_title = NULL,
    y_label = "Predicted Probability",
    shape_labels = c("Control", "Treatment")) {
    model <- fit_polr_model(data, outcome, treatment, moderators, covariates)

    preds_overall <- get_overall_preds(model, treatment, collapse_levels, shape_labels)

    preds_subgroups <- get_preds_for_subgroups(model, moderator_terms, collapse_levels, shape_labels)

    # 3. Combine
    final_preds <- bind_rows(preds_overall, preds_subgroups)

    # 4. Set factor ordering for x-axis (Overall first, then others in order)
    if (is.null(moderator_labels)) {
        final_preds$mod_group <- factor(final_preds$mod_group, levels = c("Overall", names(moderator_terms)))
    } else {
        # Use user-supplied labels (named vector)
        label_vec <- unname(unlist(moderator_labels))
        final_preds$mod_group <- factor(final_preds$mod_group, levels = c("Overall", label_vec))
        # Replace mod_group names with pretty labels if supplied
        final_preds$mod_group <- recode(final_preds$mod_group, !!!moderator_labels)
    }

    # 5. Reference line
    overall_treatment_value <- final_preds %>%
        filter(mod_group == "Overall", treatment == shape_labels[2]) %>%
        pull(predicted)

    # 6. Plot
    position <- position_dodge(width = 0.5)
    p <- ggplot(final_preds, aes(x = mod_group, y = predicted, group = treatment, shape = treatment)) +
        geom_point(size = 3, position = position) +
        geom_hline(yintercept = overall_treatment_value, linetype = "dashed", colour = "black") +
        labs(
            x = NULL,
            y = y_label,
            shape = "Treatment",
            title = plot_title
        ) +
        scale_shape_manual(values = c(1, 19)) +
        ylim(0, 1) +
        theme_classic(base_family = "serif") +
        theme(
            axis.title.x = element_text(size = 10, margin = margin(t = 10)),
            axis.title.y = element_text(size = 10, margin = margin(r = 10)),
            axis.text = element_text(size = 9),
            legend.title = element_blank(),
            legend.text = element_text(size = 9),
            plot.title = element_text(size = 9, family = "serif", hjust = 0.5),
            axis.text.x = element_text(angle = 30, hjust = 1)
        )
    return(p)
}

# Generate plot for a single outcome (modular function)
generate_plot_for_outcome <- function(
    data,
    outcome,
    treatment,
    moderators,
    covariates,
    moderator_terms,
    collapse_levels,
    moderator_labels,
    plot_title) {
    generate_ordinal_preds_plot(
        data = data,
        outcome = outcome,
        treatment = treatment,
        moderators = moderators,
        covariates = covariates,
        moderator_terms = moderator_terms,
        collapse_levels = collapse_levels,
        moderator_labels = moderator_labels,
        plot_title = plot_title
    )
}

# Defined terms and labels for each outcome
subgroups_child <- list(
    "Male" = c("ai_treatment", "profile_gender[Male]"),
    "Low Education" = c("ai_treatment", "education_recode[Low]"),
    "Working FT" = c("ai_treatment", "profile_work_stat[Working full time (30 or more hours per week)]")
)
subgroup_labels_child <- c(
    "Male" = "Male",
    "Low Education" = "Low Education",
    "Working FT" = "Working FT"
)

subgroups_trust <- list(
    "Working FT" = c("ai_treatment", "profile_work_stat[Working full time (30 or more hours per week)]")
)
subgroup_labels_trust <- c(
    "Working FT" = "Working FT"
)

subgroups_agreedisagree <- list(
    "Liberal Democrats" = c("ai_treatment", "mostlikely[Liberal Democrats]")
)
subgroup_labels_agreedisagree <- c(
    "Liberal Democrats" = "Liberal Democrats"
)


# Covariates and moderators for AI treatment
covariates_agreedisagree_ai <- c("age", "political_attention", "profile_gender", "education_recode", "profile_work_stat")
covariates_xtrust_ai <- c("age", "political_attention", "profile_gender", "education_recode", "profile_work_stat")
covariates_child_ai <- c("age", "political_attention", "profile_gender", "education_recode", "profile_work_stat", "pastvote_ge_2024", "pastvote_EURef", "profile_GOR")

# Model-specific moderators for AI treatment
moderators_agreedisagree_ai <- c("mostlikely")
moderators_xtrust_ai <- c("profile_work_stat")
moderators_child_ai <- c("profile_gender", "profile_work_stat", "education_recode")

# Covariates and moderators for Label treatment
covariates_agreedisagree_label <- NULL
covariates_xtrust_label <- NULL
covariates_child_label <- c("age", "political_attention", "education_recode", "profile_work_stat", "pastvote_ge_2024", "pastvote_EURef")

# Model-specific moderators for Label treatment
moderators_agreedisagree_label <- c("profile_GOR", "mostlikely")
moderators_xtrust_label <- c("mostlikely")
moderators_child_label <- c("profile_gender", "profile_GOR")

# === Moderator Terms and Labels for Label Treatment Plots ===

# agreedisagree: overall, political_attention, North West, West Midlands
subgroups_agreedisagree_label <- list(
    "Liberal Democrats" = c("label_treatment", "mostlikely[Liberal Democrats]"),
    "West Midlands" = c("label_treatment", "profile_GOR[West Midlands]")
)
labels_agreedisagree_label <- c(
    "Liberal Democrats" = "Liberal Democrats",
    "West Midlands" = "West Midlands"
)

subgroups_trust_label <- list(
    "Liberal Democrats" = c("label_treatment", "mostlikely[Liberal Democrats]")
)
subgroup_labels_trust_label <- c(
    "Liberal Democrats" = "Liberal Democrats"
)

subgroups_child_label <- list(
    "Male" = c("label_treatment", "profile_gender[Male]"),
    "West Midlands" = c("label_treatment", "profile_GOR[West Midlands]")
)
subgroup_labels_child_label <- c(
    "Male" = "Male",
    "West Midlands" = "West Midlands"
)
