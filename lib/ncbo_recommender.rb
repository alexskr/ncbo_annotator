require 'logger'
require 'ontologies_linked_data'
require_relative 'recommendation'

module Recommender
  module Models

    class NcboRecommender

      DEFAULT_HIERARCHY_LEVELS = 5

      def recommend(text, ontologies=[])
        # Get logger
        logger = Kernel.const_defined?("LOGGER") ? Kernel.const_get("LOGGER") : Logger.new(STDOUT)
        annotator = Annotator::Models::NcboAnnotator.new
        annotations = annotator.annotate(text, ontologies, [], false, DEFAULT_HIERARCHY_LEVELS)
        recommendations = {}
        termsMatched = []

        annotations.each do |ann|
          classId = ann.annotatedClass.id.to_s
          ont = ann.annotatedClass.submission.ontology
          ontologyId = ont.id.to_s

          unless (recommendations.include?(ontologyId))
            sub = nil

            begin
              #TODO: there appears to be a bug that does not allow retrieving submission by its id because the id is incorrect. The workaround is to get the ontology object and then retrieve its latest submission.
              sub = LinkedData::Models::Ontology.find(ont.id).first.latest_submission
              next if sub.nil?
            rescue
              logger.error(
                  "Unable to retrieve latest submission for #{ontologyId} in Recommender.")
              next
            end

            sub.bring(metrics: LinkedData::Models::Metric.attributes)
            nclasses = nil

            if !sub.loaded_attributes.include?(:metrics) || sub.metrics.nil?
              nclasses = LinkedData::Models::Class.where.in(sub).count
            else
              nclasses = sub.metrics.classes
            end
            next if nclasses.nil? || nclasses <= 0

            recommendations[ontologyId] = Recommendation.new
            recommendations[ontologyId].ontology = ont
            recommendations[ontologyId].numTermsTotal = nclasses
          end

          rec = recommendations[ontologyId]
          termsMatchedKey = "#{classId}_#{ontologyId}"

          unless termsMatched.include?(termsMatchedKey)
            termsMatched << termsMatchedKey
            rec.annotatedClasses << ann.annotatedClass
            rec.numTermsMatched += 1
          end

          rec.increment_score(ann)
        end

        vals = recommendations.values
        vals.each {|v| v.normalize_score()}
        vals.sort! {|a, b| b.score <=> a.score}

        return vals
      end

    end

  end
end